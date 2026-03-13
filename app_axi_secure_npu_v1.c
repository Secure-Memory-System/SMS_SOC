/**
 * app_axi_secure_npu_v1.c
 *
 * 동작 흐름:
 *   LCD에 숫자를 그린 뒤 BTN0를 누르면 아래 파이프라인이 순차 실행됨.
 *
 *   [BTN0 press]
 *       ↓
 *   [1] TFT LCD write_master: 내부 BRAM(28×28) → BRAM_0(0xC000_0000)
 *       ↓  (DMA done)
 *   [2] NPU V2: BRAM_0 픽셀 읽기 → Conv/Pool/Dense → digit[3:0]
 *              NPU m_axis → AES Enc s_axis  (HW 직결, 자동 실행)
 *       ↓  (NPU done_latch)
 *   [3] DMA_S2F start: AES Enc 출력(128bit) 래치 → DRAM_ENC_BUF(16 bytes)
 *       ↓  (DMA done)
 *   [4] DMA_F2S start: DRAM_ENC_BUF → AES Dec s_axis  (HW 직결)
 *       ↓  (DMA done → AES Dec → xlslice[3:0] → FND)
 *   [5] TFT LCD 내부 BRAM 클리어 → 다음 입력 준비
 */

#include "xil_io.h"
#include "xil_printf.h"
#include "xgpiops.h"
#include "sleep.h"

/* ─── Base Addresses ──────────────────────────────────────── */
#define AES_DEC_BASE    0x40000000U
#define AES_ENC_BASE    0x40001000U
#define NPU_BASE        0x40002000U
#define TFT_BASE        0x40003000U
#define DMA_F2S_BASE    0x40004000U
#define DMA_S2F_BASE    0x40005000U

/* ─── Register Offsets ────────────────────────────────────── */
/* 공통 */
#define REG_CTRL        0x00U   /* [0]=start (self-clear), TFT:[1]=bram_clear */
#define REG_STAT        0x04U   /* [0]=done pulse, TFT:[1]=busy               */
#define REG_ADDR        0x08U   /* DST_ADDR(S2F/TFT) or SRC_ADDR(F2S)        */
#define REG_LEN         0x0CU   /* 전송 바이트 수                             */

/* NPU 전용 */
#define NPU_REG_STATUS  0x00U   /* read: [1]=done_latch, [0]=busy             */
#define NPU_REG_DIGIT   0x08U   /* read: [3:0]=final_digit                    */

/* AES enc/dec 키 레지스터 (0x00~0x0C) */
#define AES_KEY_REG0    0x00U
#define AES_KEY_REG1    0x04U
#define AES_KEY_REG2    0x08U
#define AES_KEY_REG3    0x0CU

/* ─── 파라미터 ────────────────────────────────────────────── */
#define TFT_BRAM_BASE   0xC0000000U /* BRAM_0(axi_bram_ctrl_0) 주소           */
#define TFT_IMG_BYTES   784U        /* 28×28 = 784 bytes                      */
#define DRAM_ENC_BUF    0x10000000U /* 암호문 임시 저장 (PS DRAM 미사용 영역) */
#define ENC_DATA_BYTES  16U         /* AES-128 출력 = 128-bit = 16 bytes      */

/* AES-128 키 (enc/dec 동일) */
#define AES_KEY0        0x2B7E1516U
#define AES_KEY1        0x28AED2A6U
#define AES_KEY2        0xABF71588U
#define AES_KEY3        0x09CF4F3CU

/* GPIO */
#define GPIO_DEVICE_ID  0
#define BTN0_PIN        54          /* EMIO[0] = XGpioPs pin 54               */

/* poll timeout (ms) */
#define TIMEOUT_TFT_DMA     5000U
#define TIMEOUT_NPU        10000U
#define TIMEOUT_DMA_S2F     5000U
#define TIMEOUT_DMA_F2S     5000U

/* ─── 레지스터 접근 매크로 ───────────────────────────────── */
#define WR(base, off, val)  Xil_Out32((u32)(base) + (u32)(off), (u32)(val))
#define RD(base, off)       Xil_In32((u32)(base) + (u32)(off))

/* ─── 비트 폴링 (timeout_ms 초과 시 -1 반환) ────────────── */
static int poll_set(u32 base, u32 off, u32 mask, u32 timeout_ms)
{
    for (u32 t = 0; t < timeout_ms; t++) {
        if (RD(base, off) & mask)
            return 0;
        usleep(1000);
    }
    xil_printf("[ERR] poll_set timeout base=0x%08X off=0x%02X mask=0x%X\r\n",
               base, off, mask);
    return -1;
}

static int poll_clr(u32 base, u32 off, u32 mask, u32 timeout_ms)
{
    for (u32 t = 0; t < timeout_ms; t++) {
        if (!(RD(base, off) & mask))
            return 0;
        usleep(1000);
    }
    xil_printf("[ERR] poll_clr timeout base=0x%08X off=0x%02X mask=0x%X\r\n",
               base, off, mask);
    return -1;
}

/* ─── AES 키 설정 ────────────────────────────────────────── */
static void aes_set_key(u32 base)
{
    WR(base, AES_KEY_REG0, AES_KEY0);
    WR(base, AES_KEY_REG1, AES_KEY1);
    WR(base, AES_KEY_REG2, AES_KEY2);
    WR(base, AES_KEY_REG3, AES_KEY3);
}

/* ─── 파이프라인 실행 ────────────────────────────────────── */
static int run_pipeline(void)
{
    int ret;

    /* ══ Step 1: TFT LCD 내부 BRAM → BRAM_0 DMA 전송 ══════ */
    xil_printf("[1] TFT write_master start (784 bytes → 0x%08X)\r\n",
               TFT_BRAM_BASE);

    WR(TFT_BASE, REG_ADDR, TFT_BRAM_BASE);
    WR(TFT_BASE, REG_LEN,  TFT_IMG_BYTES);
    WR(TFT_BASE, REG_CTRL, 0x1);           /* start */

    /* busy[1] 올라올 때까지 잠시 대기 후, busy가 내려올 때 완료 */
    poll_set(TFT_BASE, REG_STAT, 0x2, 100);    /* busy=1 확인 (최대 100ms) */
    ret = poll_clr(TFT_BASE, REG_STAT, 0x2, TIMEOUT_TFT_DMA);
    if (ret) return ret;
    xil_printf("[1] TFT DMA done\r\n");

    /* ══ Step 2: NPU 추론 시작 ════════════════════════════ */
    /* NPU done 후 AXI-Stream으로 digit → AES Enc 자동 암호화.
     * AES Enc는 output_valid=1로 결과를 유지하며 DMA_S2F가
     * 준비될 때까지 기다림 (m_axis_tready 대기). */
    xil_printf("[2] NPU start\r\n");
    WR(NPU_BASE, REG_CTRL, 0x1);           /* start (self-clear) */

    /* read 0x00: bit[1]=done_latch, bit[0]=busy */
    ret = poll_set(NPU_BASE, NPU_REG_STATUS, 0x2, TIMEOUT_NPU);
    if (ret) return ret;

    u32 digit = RD(NPU_BASE, NPU_REG_DIGIT) & 0xFU;
    xil_printf("[2] NPU done → digit = %d\r\n", (int)digit);

    /* ══ Step 3: DMA_S2F start → AES Enc 출력(16B) → DRAM ═ */
    /* NPU 완료 시점에 AES Enc는 이미 암호화 완료 후 대기 중.
     * DMA_S2F를 start하면 s_axis_tready 올라가며 즉시 수신. */
    xil_printf("[3] DMA_S2F start (enc 16 bytes → 0x%08X)\r\n",
               DRAM_ENC_BUF);

    WR(DMA_S2F_BASE, REG_ADDR, DRAM_ENC_BUF);
    WR(DMA_S2F_BASE, REG_LEN,  ENC_DATA_BYTES);
    WR(DMA_S2F_BASE, REG_CTRL, 0x1);       /* start */

    ret = poll_set(DMA_S2F_BASE, REG_STAT, 0x1, TIMEOUT_DMA_S2F);
    if (ret) return ret;
    xil_printf("[3] DMA_S2F done (encrypted data in DRAM)\r\n");

    /* ══ Step 4: DMA_F2S start → DRAM → AES Dec → FND ════ */
    /* DMA_F2S가 DRAM에서 읽어 AXI-Stream으로 AES Dec에 전달.
     * AES Dec → xlslice[3:0] → FND (모두 HW 자동). */
    xil_printf("[4] DMA_F2S start (0x%08X → AES Dec → FND)\r\n",
               DRAM_ENC_BUF);

    WR(DMA_F2S_BASE, REG_ADDR, DRAM_ENC_BUF);
    WR(DMA_F2S_BASE, REG_LEN,  ENC_DATA_BYTES);
    WR(DMA_F2S_BASE, REG_CTRL, 0x1);       /* start */

    ret = poll_set(DMA_F2S_BASE, REG_STAT, 0x1, TIMEOUT_DMA_F2S);
    if (ret) return ret;
    xil_printf("[4] DMA_F2S done → FND displays %d\r\n", (int)digit);

    /* ══ Step 5: TFT LCD 내부 BRAM 클리어 ════════════════ */
    WR(TFT_BASE, REG_CTRL, 0x2);           /* bram_clear (bit[1]) */
    xil_printf("[5] TFT BRAM cleared. Draw next digit.\r\n");

    return 0;
}

/* ─── main ───────────────────────────────────────────────── */
int main(void)
{
    xil_printf("\r\n=== Secure NPU SoC App v1 ===\r\n");
    xil_printf("Flow: TFT → BTN0 → NPU → AES_Enc → DMA → AES_Dec → FND\r\n\r\n");

    /* GPIO 초기화 */
    XGpioPs      gpio;
    XGpioPs_Config *cfg = XGpioPs_LookupConfig(GPIO_DEVICE_ID);
    if (!cfg) {
        xil_printf("[ERR] GPIO config not found\r\n");
        return -1;
    }
    XGpioPs_CfgInitialize(&gpio, cfg, cfg->BaseAddr);
    XGpioPs_SetDirectionPin(&gpio, BTN0_PIN, 0);  /* input */

    /* AES 키 초기화 (enc/dec 동일) */
    aes_set_key(AES_ENC_BASE);
    aes_set_key(AES_DEC_BASE);
    xil_printf("AES-128 keys initialized.\r\n");
    xil_printf("Draw a digit on LCD, then press BTN0.\r\n\r\n");

    u32 prev_btn = 0;

    while (1) {
        u32 btn = XGpioPs_ReadPin(&gpio, BTN0_PIN);

        /* rising edge 감지 */
        if (btn && !prev_btn) {
            usleep(20000);  /* 20ms debounce */
            if (XGpioPs_ReadPin(&gpio, BTN0_PIN)) {
                xil_printf("──── BTN0 pressed ────\r\n");
                if (run_pipeline() != 0)
                    xil_printf("[ERR] Pipeline failed!\r\n");
                xil_printf("\r\n");
            }
        }
        prev_btn = btn;
    }

    return 0;
}
