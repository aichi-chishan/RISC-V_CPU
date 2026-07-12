#include "../include/rvcpu_soc.h"

// 最小“贪吃蛇式”显示演示：不依赖 C 库，CPU 直接用 SH 写 RGB565 帧缓冲，
// 每次 vblank 移动一格并擦除尾部。接入按键/UART RX 后可替换自动转向逻辑。
typedef struct { uint16_t x,y; } point_t;
static point_t snake[32];
static unsigned head,tail,length;

static void draw_cell(point_t p,uint16_t color){
    unsigned px=p.x*4,py=p.y*4,x,y;
    for(y=0;y<4;y++)for(x=0;x<4;x++)gpu_put_pixel(px+x,py+y,color);
}
static void clear_screen(uint16_t color){
    unsigned i;volatile uint16_t *fb=(volatile uint16_t *)(uintptr_t)RVCPU_FB_BASE;
    for(i=0;i<320u*240u;i++)fb[i]=color;
}

int main(void){
    unsigned i;int dx=1,dy=0;point_t next;
    const uint16_t black=rgb565(0,0,0),green=rgb565(0,255,40),food=rgb565(255,80,0);
    clear_screen(black);
    for(i=0;i<8;i++){snake[i].x=20+i;snake[i].y=20;draw_cell(snake[i],green);}
    head=7;tail=0;length=8;draw_cell((point_t){60,40},food);
    GPU_CTRL=GPU_ENABLE|GPU_VBLANK_IRQ_EN;
    for(;;){
        gpu_wait_vblank();
        next=snake[head];next.x=(uint16_t)(next.x+dx);next.y=(uint16_t)(next.y+dy);
        // 自动沿屏幕边缘转向，形成持续可见的闭环运动。
        if(next.x>=79){dx=0;dy=1;next=snake[head];next.y++;}
        if(next.y>=59){dx=-1;dy=0;next=snake[head];next.x--;}
        if(next.x==0&&dx<0){dx=0;dy=-1;next=snake[head];next.y--;}
        if(next.y==0&&dy<0){dx=1;dy=0;next=snake[head];next.x++;}
        draw_cell(snake[tail],black);tail=(tail+1u)%32u;
        head=(head+1u)%32u;snake[head]=next;draw_cell(next,green);
        (void)length;
    }
}
