# 🔐 Secure Memory System (SMS) SoC

> AES-128 암호화 기반 보안 메모리 시스템 — Zynq-7000 SoC 구현

[![Vivado](https://img.shields.io/badge/Vivado-2024.2-blue)](https://www.xilinx.com/products/design-tools/vivado.html)
[![Board](https://img.shields.io/badge/Board-Zybo%20Z7--20-green)](https://digilent.com/reference/programmable-logic/zybo-z7/start)
[![Encryption](https://img.shields.io/badge/Encryption-AES--128-red)](https://en.wikipedia.org/wiki/Advanced_Encryption_Standard)

---

## 📌 프로젝트 개요

LCD에서 입력된 **손글씨 숫자 4자리**를 NPU가 인식하고, 인식 결과를 **AES-128 암호화**하여 DRAM에 안전하게 저장한 뒤, 복호화하여 **FND(7-Segment Display)** 로 출력하는 보안 메모리 시스템입니다.

```
LCD 입력 (손글씨 4자리) ──────────────────────────────▶ FND 출력 (1234)
```

---

## 🔄 보안 데이터 흐름

```
LCD → DRAM_0 → DMA → NPU → 암호화 IP → DMA → DRAM_1 → DMA → 복호화 IP → FND
                                          (암호화된 상태로 저장)
```

| 단계 | 구성 요소 | 설명 |
|------|-----------|------|
| 1. 입력 및 초기 저장 | LCD → DRAM_0 | 손글씨 4자리 숫자 입력 및 원시 픽셀 데이터 저장 |
| 2. 데이터 처리 | DMA → NPU → 암호화 IP | 픽셀 데이터를 NPU가 숫자로 변환, 즉시 AES-128 암호화 |
| 3. 보안 저장 | DMA → DRAM_1 | 암호화된 상태로 DRAM_1에 안전하게 저장 |
| 4. 출력 및 복호화 | DMA → 복호화 IP → FND | 필요 시 복호화하여 FND에 숫자 출력 |

---

## 🛠️ 개발 환경

| 항목 | 사양 |
|------|------|
| **보드** | Digilent Zybo Z7-20 |
| **FPGA** | Xilinx Zynq-7000 (xc7z020clg400-1) |
| **PS CPU** | ARM Cortex-A9 Dual-Core @ 667MHz |
| **DDR** | DDR3 512MB |
| **EDA 도구** | Xilinx Vivado 2024.2 |
| **OS** | Windows 10/11 64-bit |
| **라이선스** | Xilinx WebPACK (무료) |

---

## 📦 IP 구성 목록

| IP 이름 | 종류 | 역할 |
|---------|------|------|
| `npu_axi_wrapper` | 커스텀 IP | 손글씨 → 숫자 변환 (NPU 래퍼) |
| `aes_enc_axi_wrapper` | 커스텀 IP | AES-128 암호화 |
| `aes_dec_axi_wrapper` | 커스텀 IP | AES-128 복호화 |
| `top_dma_full_to_stream` | 커스텀 IP | DRAM → AXI-Stream 출력 (×2) |
| `top_dma_stream_to_full` | 커스텀 IP | AXI-Stream → DRAM 저장 (×1) |
| `ZYNQ7 Processing System` | Xilinx IP | ARM Cortex-A9 PS, DDR 컨트롤러 내장 |
| `AXI Interconnect` | Xilinx IP | AXI-Lite 제어 버스 라우팅 |
| `AXI SmartConnect` | Xilinx IP | AXI-Full 메모리 버스 라우팅 (×3) |
| `AXI4-Stream Data Width Converter` | Xilinx IP | 32bit → 128bit 폭 변환 |

---

## 📁 프로젝트 구조

```
SMS_SOC_GIT/
├── secure_memory_soc_v0.1/
│   ├── myip_zybo_z7_20.xpr          # Vivado 프로젝트 파일
│   ├── myip_zybo_z7_20.srcs/
│   │   └── sources_1/
│   │       ├── bd/soc_design/       # Block Design
│   │       └── new/                 # 커스텀 IP 소스
│   │           ├── aes_128_core.v
│   │           ├── aes_128_inv_core.v
│   │           ├── aes_enc_axi_wrapper.v
│   │           ├── aes_dec_axi_wrapper.v
│   │           ├── aes_key_expansion.v
│   │           ├── npu_axi_wrapper.v
│   │           ├── npu_top.v
│   │           ├── top_dma_full_to_stream.v
│   │           ├── top_dma_stream_to_full.v
│   │           └── ...
│   └── tb_npu_top_behav.wcfg        # 파형 설정 파일
├── docs/                            # 기술 문서
└── .gitignore
```

---

## 🚀 시작하기

### 1. 클론
```bash
git clone https://github.com/Secure-Memory-System/SMS_SOC.git
```

### 2. Vivado에서 프로젝트 열기
```
File → Open Project → secure_memory_soc_v0.1/myip_zybo_z7_20.xpr
```

### 3. IP 재생성
프로젝트를 처음 열면 IP 재생성 메시지가 표시됩니다.
```
"IP needs to be regenerated" → Generate 또는 Upgrade IP 클릭
```

### 4. Block Design 열기
```
Sources 패널 → Design Sources → soc_design.bd 더블클릭
```

### 5. 빌드
```
Validate Design (F6) → Generate Block Design → Create HDL Wrapper → Generate Bitstream
```

---

## 🗺️ 주소 맵

| IP | Base Address | 크기 |
|----|-------------|------|
| top_dma_full_to_stre_0 | 0x4300_0000 | 4 KB |
| top_dma_full_to_stre_1 | 0x4301_0000 | 4 KB |
| top_dma_stream_to_fu_0 | 0x4302_0000 | 4 KB |
| npu_axi_wrapper_0 | 0x4303_0000 | 4 KB |
| aes_enc_axi_wrapper_0 | 0x4304_0000 | 4 KB |
| aes_dec_axi_wrapper_0 | 0x4305_0000 | 4 KB |

---

## ⚠️ 알려진 경고 (무시 가능)

| 경고 ID | 내용 | 처리 방법 |
|---------|------|-----------|
| BD 41-2559 | m_axis_0 포트 클럭 미연결 | 무시 가능 (동작에 영향 없음) |
| PSU-1~4 | DDR DQS 스큐 음수값 | 무시 (보드 제조사 정확한 값) |

---

## 🔧 향후 구현 과제

| 구분 | 항목 | 설명 |
|------|------|------|
| 하드웨어 | FND 컨트롤러 IP | m_axis 출력을 받아 7-Segment에 숫자를 표시하는 IP |
| 하드웨어 | LCD 입력 인터페이스 | 터치 LCD에서 손글씨를 입력받아 DRAM_0에 저장하는 IP |
| 소프트웨어 | ARM 펌웨어 (Vitis) | DMA 제어, AES 키 설정, 인터럽트 처리 |
| 소프트웨어 | NPU 가중치 파일 | fc_weights.mem 파일 생성 및 프로젝트 등록 |
| 검증 | 시스템 통합 테스트 | 전체 파이프라인 동작 검증 |

---

## 📄 문서

자세한 구현 가이드는 [`docs/`](./docs) 폴더를 참고하세요.
