/*
 * Secure Memory SoC - Full Pipeline Debug Code (Fixed & Continuous)
 * Pipeline: LCD → BRAM → NPU → AES_ENC → DMA_S2F → DRAM → DMA_F2S → AES_DEC → FND
 */

#include "xparameters.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xgpiops.h"
#include "sleep.h"
#include "xil_cache.h"

/* ============================================================
 * 베이스 주소
 * ============================================================ */
#define AES_DEC_BASE    0x40000000UL
#define AES_ENC_BASE    0x40001000UL
#define NPU_BASE        0x40002000UL
#define TFT_BASE        0x40003000UL
#define DMA_F2S_BASE    0x40004000UL
#define DMA_S2F_BASE    0x40005000UL
#define BRAM_BASE       0x42000000UL   /* LCD DMA 목적지 */
#define DRAM_ENC_BUF    0x00200000UL   /* 암호문 저장 DDR 영역 */

/* ============================================================
 * GPIO (BTN0) - Zybo Z7 BTN0 = MIO 54번 핀
 * ============================================================ */
#define BTN0_PIN        54

/* ============================================================
 * AES 128-bit 테스트 키
 * ============================================================ */
#define AES_KEY_W0      0x2B7E1516
#define AES_KEY_W1      0x28AED2A6
#define AES_KEY_W2      0xABF71588
#define AES_KEY_W3      0x09CF4F3C

/* ============================================================
 * 유틸리티 함수: 폴링 대기
 * ============================================================ */
static int poll_done(u32 base, u32 offset, u32 mask, u32 expected, const char* name) {
    u32 cnt = 0;
    u32 stat = 0;
    while (cnt++ < 100000) { // 타임아웃 약 1초 (10us * 100000)
        stat = Xil_In32(base + offset);
        if ((stat & mask) == expected) {
            return 0; // 성공
        }
        usleep(10);
    }
    xil_printf("[%s] ERROR: 타임아웃 발생! (STAT=0x%08X)\r\n", name, stat);
    return -1;
}

/* ============================================================
 * 메인 파이프라인 실행 함수
 * ============================================================ */
static void run_pipeline(int test_cnt) {
    int ret;
    xil_printf("\r\n################################################\r\n");
    xil_printf(" [TEST #%d] 새로운 파이프라인 사이클 시작\r\n", test_cnt);
    xil_printf("################################################\r\n");

    /* 0. DRAM 버퍼 초기화 (이전 쓰레기값 제거) */
    for (int i = 0; i < 4; i++) {
        Xil_Out32(DRAM_ENC_BUF + i * 4, 0xDEADBEEF);
    }
    Xil_DCacheFlushRange(DRAM_ENC_BUF, 16);

    /* --------------------------------------------------------
     * STEP 1: LCD 터치패드 → BRAM 전송
     * -------------------------------------------------------- */
    xil_printf("[TFT] BRAM(0x%08X)으로 픽셀 전송 중...\r\n", BRAM_BASE);
    Xil_Out32(TFT_BASE + 0x08, BRAM_BASE);
    Xil_Out32(TFT_BASE + 0x0C, 784);
    Xil_Out32(TFT_BASE + 0x00, 0x1);

    ret = poll_done(TFT_BASE, 0x04, 0x1, 0x1, "TFT_DMA");
    if (ret != 0) return;
    
    /* 캐시 무효화 후 BRAM 덤프 시각화 */
    Xil_DCacheInvalidateRange(BRAM_BASE, 784 * 4);
    xil_printf("[DBG] BRAM 28x28 이미지 확인:\r\n");
    for (int row = 0; row < 28; row++) {
        for (int col = 0; col < 28; col++) {
            int pixel_idx = row * 28 + col;
            u32 word = Xil_In32(BRAM_BASE + (pixel_idx / 4) * 4);
            u8 pixel = (word >> ((pixel_idx % 4) * 8)) & 0xFF;
            
            if (pixel > 128)      xil_printf("#");
            else if (pixel > 0)   xil_printf(".");
            else                  xil_printf(" ");
        }
        xil_printf("\r\n");
    }

    /* --------------------------------------------------------
     * STEP 2: DMA S2F 대기 + NPU 추론 + AES 암호화
     * -------------------------------------------------------- */
    xil_printf("[SYS] NPU 연산 및 AES 암호화 파이프라인 가동...\r\n");
    
    /* DMA S2F (Stream to DRAM) 수신 대기 */
    Xil_Out32(DMA_S2F_BASE + 0x08, DRAM_ENC_BUF);
    Xil_Out32(DMA_S2F_BASE + 0x0C, 16); // 128-bit
    Xil_Out32(DMA_S2F_BASE + 0x00, 0x1);

    /* NPU 가동 (오프셋 버그 수정됨: 0x00000000) */
    Xil_Out32(NPU_BASE + 0x04, 0x00000000); 
    Xil_Out32(NPU_BASE + 0x00, 0x00000001);

    /* NPU 및 DMA 완료 대기 */
    if (poll_done(NPU_BASE, 0x00, 0x2, 0x2, "NPU") != 0) return;
    if (poll_done(DMA_S2F_BASE, 0x04, 0x1, 0x1, "DMA_S2F") != 0) return;

    u32 npu_digit = Xil_In32(NPU_BASE + 0x08) & 0xF;

    /* --------------------------------------------------------
     * STEP 3: DRAM 암호화 데이터 확인
     * -------------------------------------------------------- */
    Xil_DCacheInvalidateRange(DRAM_ENC_BUF, 16);
    u32 enc0 = Xil_In32(DRAM_ENC_BUF + 0x00);
    u32 enc1 = Xil_In32(DRAM_ENC_BUF + 0x04);
    u32 enc2 = Xil_In32(DRAM_ENC_BUF + 0x08);
    u32 enc3 = Xil_In32(DRAM_ENC_BUF + 0x0C);

    xil_printf("[DRAM] 기록된 암호문 (128-bit):\r\n");
    xil_printf("  -> %08X_%08X_%08X_%08X\r\n", enc3, enc2, enc1, enc0);

    /* --------------------------------------------------------
     * STEP 4: 복호화 (DMA F2S -> AES DEC -> FND)
     * -------------------------------------------------------- */
    xil_printf("[SYS] AES 복호화 및 FND 출력 파이프라인 가동...\r\n");
    Xil_DCacheFlushRange(DRAM_ENC_BUF, 16); // DMA 읽기 전 캐시 반영
    
    Xil_Out32(DMA_F2S_BASE + 0x08, DRAM_ENC_BUF);
    Xil_Out32(DMA_F2S_BASE + 0x0C, 16);
    Xil_Out32(DMA_F2S_BASE + 0x00, 0x1);

    if (poll_done(DMA_F2S_BASE, 0x04, 0x1, 0x1, "DMA_F2S") != 0) return;

    /* --------------------------------------------------------
     * 결과 요약
     * -------------------------------------------------------- */
    xil_printf("\r\n+-------------------------------------------+\r\n");
    xil_printf("|  [최종 결과 요약]                         |\r\n");
    xil_printf("|  NPU 판정 결과         : %u                |\r\n", npu_digit);
    xil_printf("|  FND(7-Seg) 표시 상태   : 직접 확인 필요     |\r\n");
    xil_printf("+-------------------------------------------+\r\n");

    /* 다음 입력을 위해 LCD BRAM 초기화 */
    Xil_Out32(TFT_BASE + 0x00, 0x2);
    usleep(1000);
    xil_printf("[SYS] 캔버스 초기화 완료. 다음 숫자를 그리고 BTN0을 누르세요!\r\n");
}

/* ============================================================
 * main
 * ============================================================ */
int main(void) {
    xil_printf("\r\n==============================================\r\n");
    xil_printf("  Secure Memory SoC v1.0 (Full Pipeline)\r\n");
    xil_printf("==============================================\r\n");

    /* 1. AES 키 설정 (루프 밖에서 최초 1회만) */
    xil_printf("[INIT] AES 암호화/복호화 키 세팅 중...\r\n");
    Xil_Out32(AES_ENC_BASE + 0x00, AES_KEY_W0);
    Xil_Out32(AES_ENC_BASE + 0x04, AES_KEY_W1);
    Xil_Out32(AES_ENC_BASE + 0x08, AES_KEY_W2);
    Xil_Out32(AES_ENC_BASE + 0x0C, AES_KEY_W3);

    Xil_Out32(AES_DEC_BASE + 0x00, AES_KEY_W0);
    Xil_Out32(AES_DEC_BASE + 0x04, AES_KEY_W1);
    Xil_Out32(AES_DEC_BASE + 0x08, AES_KEY_W2);
    Xil_Out32(AES_DEC_BASE + 0x0C, AES_KEY_W3);
    xil_printf("[INIT] 키 세팅 완료!\r\n");

    /* 2. GPIO 초기화 (BTN0) */
    XGpioPs gpio;
    XGpioPs_Config *gpio_cfg = XGpioPs_LookupConfig(0);
    XGpioPs_CfgInitialize(&gpio, gpio_cfg, XPAR_XGPIOPS_0_BASEADDR);
    XGpioPs_SetDirectionPin(&gpio, BTN0_PIN, 0); 
    xil_printf("[GPIO] BTN0 초기화 완료. 터치패드 대기 중...\r\n");

    u32 btn_prev = 0;
    int test_cnt = 1;

    /* 3. 무한 폴링 루프 (버튼 클릭 감지) */
    while (1) {
        u32 btn_now = XGpioPs_ReadPin(&gpio, BTN0_PIN);

        /* 버튼 상승 엣지(Rising Edge) 감지 */
        if (btn_now == 1 && btn_prev == 0) {
            usleep(20000);  /* 디바운싱 20ms */
            if (XGpioPs_ReadPin(&gpio, BTN0_PIN) == 1) {
                run_pipeline(test_cnt++);
            }
        }
        btn_prev = btn_now;
        usleep(10000);  /* 10ms 단위 폴링 */
    }

    return 0;
}