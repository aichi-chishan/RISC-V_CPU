#ifndef RVCPU_SOC_H
#define RVCPU_SOC_H
#include <stdint.h>

#define RVCPU_GPIO_BASE  0x40000000u
#define RVCPU_UART_BASE  0x40001000u
#define RVCPU_GPU_BASE   0x40002000u
#define RVCPU_FB_BASE    0x50000000u
#define RVCPU_CLINT_BASE 0x02000000u

#define MMIO32(a) (*(volatile uint32_t *)(uintptr_t)(a))
#define GPU_CTRL       MMIO32(RVCPU_GPU_BASE+0x00)
#define GPU_STATUS     MMIO32(RVCPU_GPU_BASE+0x04)
#define GPU_SIZE       MMIO32(RVCPU_GPU_BASE+0x08)
#define GPU_BACKGROUND MMIO32(RVCPU_GPU_BASE+0x0c)
#define GPU_ENABLE       (1u<<0)
#define GPU_VBLANK_IRQ_EN (1u<<1)

static inline uint16_t rgb565(uint8_t r,uint8_t g,uint8_t b){
    return (uint16_t)(((r>>3)<<11)|((g>>2)<<5)|(b>>3));
}
static inline void gpu_put_pixel(unsigned x,unsigned y,uint16_t color){
    if(x<320&&y<240)((volatile uint16_t *)(uintptr_t)RVCPU_FB_BASE)[y*320+x]=color;
}
static inline void gpu_wait_vblank(void){
    while((GPU_STATUS&1u)==0u){} GPU_STATUS=1u;
}
#endif
