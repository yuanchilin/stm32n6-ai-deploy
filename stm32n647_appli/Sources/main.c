/**
 ******************************************************************************
 * @file           : main.c
 * @author         : STM32 AI Inference Demo
 * @brief          : STM32N647 AI network inference example using ST.AI middleware
 *                   - Model: matrix_mul (fully connected: 4 inputs -> 2 outputs)
 *                   - Data type: float32
 *                   - Output: UART (USART1) at 115200 baud
 ******************************************************************************
 * @attention
 *
 * This software is licensed under terms that can be found in the LICENSE file
 * in the root directory of this software component.
 * If no LICENSE file comes with this software, it is provided AS-IS.
 *
 ******************************************************************************
 */

#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include "stai.h"
#include "network.h"
#include "network_data.h"

/*============================================================================*/
/*                     STM32N647 Register Definitions                         */
/*============================================================================*/
/* NOTE: Adjust these base addresses and pin configurations to match your
   specific hardware board (e.g. STM32N6570-DK Discovery Kit). */

/* System Control Block */
#define SCB_CPACR               (*(volatile uint32_t *)0xE000ED88UL)

/* RCC (Reset and Clock Control) */
#define RCC_BASE                0x46000000UL
#define RCC_APB1ENR1            (*(volatile uint32_t *)(RCC_BASE + 0x90))
#define RCC_APB2ENR             (*(volatile uint32_t *)(RCC_BASE + 0xA0))
#define RCC_AHB5ENR             (*(volatile uint32_t *)(RCC_BASE + 0xC8))

/* GPIO Port B (example: PB6=TX, PB7=RX for USART1) */
#define GPIOB_BASE              0x42020400UL
#define GPIOB_MODER             (*(volatile uint32_t *)(GPIOB_BASE + 0x00))
#define GPIOB_AFRL              (*(volatile uint32_t *)(GPIOB_BASE + 0x20))
#define GPIOB_AFRH              (*(volatile uint32_t *)(GPIOB_BASE + 0x24))

/* USART1 (adjust base address per reference manual) */
#define USART1_BASE             0x400C0000UL
#define USART1_CR1              (*(volatile uint32_t *)(USART1_BASE + 0x00))
#define USART1_CR2              (*(volatile uint32_t *)(USART1_BASE + 0x04))
#define USART1_BRR              (*(volatile uint32_t *)(USART1_BASE + 0x0C))
#define USART1_ISR              (*(volatile uint32_t *)(USART1_BASE + 0x1C))
#define USART1_TDR              (*(volatile uint32_t *)(USART1_BASE + 0x28))
#define USART1_RDR              (*(volatile uint32_t *)(USART1_BASE + 0x24))

/*============================================================================*/
/*                         System Clock Configuration                         */
/*============================================================================*/
/* Default system clock is HSI (64 MHz) for STM32N6 series.
   For production, configure PLL for higher frequency. */

#define SYSTEM_CLOCK_HZ         64000000UL
#define UART_BAUDRATE           115200UL

/*============================================================================*/
/*                         Function Prototypes                                */
/*============================================================================*/
void SystemInit(void);
static void FPU_Init(void);
static void UART_Init(void);

/*============================================================================*/
/*                          UART Low-Level I/O                                */
/*============================================================================*/

/**
 * @brief  Retarget putchar for printf output via USART1
 * @param  ch  Character to send
 * @retval Character sent (or EOF on error)
 */
int __io_putchar(int ch)
{
    /* Wait for TX buffer empty (TXE flag, bit 7) */
    while (!(USART1_ISR & (1UL << 7))) { }
    /* Write character to transmit data register */
    USART1_TDR = (uint32_t)(ch & 0xFF);

    /* Handle CR -> CRLF translation for terminal compatibility */
    if (ch == '\n') {
        while (!(USART1_ISR & (1UL << 7))) { }
        USART1_TDR = 0x0D;  /* Send carriage return */
    }

    return ch;
}

/**
 * @brief  Retarget getchar for input via USART1
 * @retval Character received
 */
int __io_getchar(void)
{
    /* Wait for RX buffer not empty (RXNE flag, bit 5) */
    while (!(USART1_ISR & (1UL << 5))) { }
    return (int)(USART1_RDR & 0xFF);
}

/*============================================================================*/
/*                       FPU Initialization                                   */
/*============================================================================*/

/**
 * @brief  Enable the FPU (Floating Point Unit) for Cortex-M55
 * @note   The CPACR register enables access to CP10/CP11 (FPU).
 *         Full access is granted by setting bits 20-23 to 0xF.
 *         Cortex-M55 also has CP2 for MVE (Helium), enabled separately.
 */
static void FPU_Init(void)
{
    /* Enable CP10 and CP11 (FPU) with full access */
    SCB_CPACR |= (0xFUL << 20);

    /* Data synchronization barrier to ensure write completes */
    __asm volatile("dsb" ::: "memory");
    __asm volatile("isb" ::: "memory");
}

/*============================================================================*/
/*                         UART Initialization                                */
/*============================================================================*/

/**
 * @brief  Initialize USART1 at 115200 baud, 8N1
 * @note   USART1 TX/RX pins need to be configured according to your board.
 *         Example below assumes PB6 (TX) and PB7 (RX) with alternate function 7.
 *         Change GPIO port/pins and AF value to match your hardware.
 */
static void UART_Init(void)
{
    /*--- Step 1: Enable peripheral clocks ---*/

    /* Enable GPIOB clock (AHB5 bit 1: GPIOBEN) */
    RCC_AHB5ENR |= (1UL << 1);

    /* Enable USART1 clock (APB2 bit 14: USART1EN) */
    RCC_APB2ENR |= (1UL << 14);

    /*--- Step 2: Configure GPIO pins as alternate function ---*/

    /* PB6 (TX):  MODER[13:12] = 10 (alternate function mode)
       PB7 (RX):  MODER[15:14] = 10 (alternate function mode) */
    GPIOB_MODER &= ~((3UL << 12) | (3UL << 14));
    GPIOB_MODER |=  ((2UL << 12) | (2UL << 14));

    /* Set alternate function AF7 (USART1) for PB6 and PB7
       AFRL controls Pins 0-7, each pin uses 4 bits.
       PB6 -> AFRL bits [27:24] = 0x7 (AF7)
       PB7 -> AFRL bits [31:28] = 0x7 (AF7) */
    GPIOB_AFRL &= ~(0xFFUL << 24);
    GPIOB_AFRL |=  (0x77UL << 24);

    /*--- Step 3: Configure USART1 ---*/

    /* Disable USART1 before configuration */
    USART1_CR1 = 0;

    /* Set baud rate: BRR = clock / baudrate */
    USART1_BRR = SYSTEM_CLOCK_HZ / UART_BAUDRATE;

    /* Configure: 8 data bits, 1 stop bit, no parity, enable TX & RX
       UE (bit 0): USART enable
       RE (bit 2): Receiver enable
       TE (bit 3): Transmitter enable */
    USART1_CR1 = (1UL << 0) |   /* UE  - USART enable */
                 (1UL << 2) |   /* RE  - Receiver enable */
                 (1UL << 3);    /* TE  - Transmitter enable */
}

/*============================================================================*/
/*                           Helper Functions                                 */
/*============================================================================*/

/**
 * @brief  Print a float array in a formatted way via printf
 */
static void print_float_array(const char *label, const float *data, int len)
{
    printf("%s: [", label);
    for (int i = 0; i < len; i++) {
        printf("%.6f", (double)data[i]);
        if (i < len - 1) {
            printf(", ");
        }
    }
    printf("]\r\n");
}

/*============================================================================*/
/*                        System Initialization                               */
/*============================================================================*/

/**
 * @brief  System initialization called by the startup code before main()
 * @note   This function initializes the FPU, system clock, and UART.
 *         It is called by Reset_Handler in startup_stm32n647a0hxq.s via BL SystemInit.
 */
void SystemInit(void)
{
    /* Initialize FPU for float32 operations */
    FPU_Init();

    /* Initialize UART for printf output */
    UART_Init();
}

/*============================================================================*/
/*                               Main Program                                 */
/*============================================================================*/

int main(void)
{
    stai_return_code ret;
    stai_network *network;
    stai_ptr inputs[STAI_NETWORK_IN_NUM];
    stai_ptr outputs[STAI_NETWORK_OUT_NUM];
    stai_ptr activations[STAI_NETWORK_ACTIVATIONS_NUM];
    float *input_ptr;
    float *output_ptr;

    /* Allocate network context buffer (must be aligned) */
    uint8_t network_ctx_buf[STAI_NETWORK_CONTEXT_SIZE]
        __attribute__((aligned(STAI_NETWORK_CONTEXT_ALIGNMENT)));

    /* Allocate activations buffer (includes memory for inputs and outputs) */
    uint8_t activations_buf[STAI_NETWORK_ACTIVATIONS_SIZE_BYTES]
        __attribute__((aligned(4)));

    /* Example input: 4-element float vector
     * The network implements a fully connected layer: y = W * x + b
     * where W is 2x4 and b is 2x1 */
    float input_data[STAI_NETWORK_IN_1_SIZE] = { 1.0f, 2.0f, 3.0f, 4.0f };

    /*========================================================================*/
    /*  Print banner                                                          */
    /*========================================================================*/
    printf("\r\n");
    printf("============================================\r\n");
    printf("  STM32N647 AI Network Inference Demo\r\n");
    printf("============================================\r\n");
    printf("  Model:       %s\r\n", STAI_NETWORK_ORIGIN_MODEL_NAME);
    printf("  C Name:      %s\r\n", STAI_NETWORK_MODEL_NAME);
    printf("  Signature:   0x%08llX\r\n",
           (unsigned long long)STAI_NETWORK_MODEL_SIGNATURE);
    printf("  Inputs:      %d x float32 (shape: {1,%d})\r\n",
           STAI_NETWORK_IN_1_SIZE, STAI_NETWORK_IN_1_CHANNEL);
    printf("  Outputs:     %d x float32 (shape: {1,%d})\r\n",
           STAI_NETWORK_OUT_1_SIZE, STAI_NETWORK_OUT_1_CHANNEL);
    printf("  MACCs:       %d\r\n", STAI_NETWORK_MACC_NUM);
    printf("  Weights:     %d bytes\r\n", STAI_NETWORK_WEIGHTS_SIZE_BYTES);
    printf("  Activations: %d bytes\r\n", STAI_NETWORK_ACTIVATIONS_SIZE_BYTES);
    printf("============================================\r\n\r\n");

    /*========================================================================*/
    /*  Step 1: Initialize Network Context                                    */
    /*========================================================================*/
    network = (stai_network *)network_ctx_buf;

    ret = stai_network_init(network);
    if (ret != STAI_SUCCESS) {
        printf("[ERROR] stai_network_init failed! return_code = %d\r\n", ret);
        goto error_halt;
    }
    printf("[OK] Network context initialized (%u bytes)\r\n",
           (unsigned int)STAI_NETWORK_CONTEXT_SIZE);

    /*========================================================================*/
    /*  Step 2: Set Activations Buffer                                       */
    /*========================================================================*/
    /* The activation buffer provides working memory for the network.
       Internally, set_activations also carves out input (offset 0)
       and output (offset 16) sub-buffers from the activation area. */
    activations[0] = (stai_ptr)activations_buf;

    ret = stai_network_set_activations(network, activations,
                                       STAI_NETWORK_ACTIVATIONS_NUM);
    if (ret != STAI_SUCCESS) {
        printf("[ERROR] stai_network_set_activations failed! return_code = %d\r\n", ret);
        goto error_halt;
    }
    printf("[OK] Activations buffer set (@ 0x%08lX, %d bytes)\r\n",
           (unsigned long)(uintptr_t)activations_buf,
           (int)STAI_NETWORK_ACTIVATIONS_SIZE_BYTES);

    /*========================================================================*/
    /*  Step 3: Get Input/Output Buffer Pointers                             */
    /*========================================================================*/
    ret = stai_network_get_inputs(network, inputs, NULL);
    if (ret != STAI_SUCCESS) {
        printf("[ERROR] stai_network_get_inputs failed! return_code = %d\r\n", ret);
        goto error_halt;
    }

    ret = stai_network_get_outputs(network, outputs, NULL);
    if (ret != STAI_SUCCESS) {
        printf("[ERROR] stai_network_get_outputs failed! return_code = %d\r\n", ret);
        goto error_halt;
    }

    input_ptr  = (float *)inputs[0];
    output_ptr = (float *)outputs[0];

    printf("[OK] Input buffer  @ 0x%08lX (%d floats)\r\n",
           (unsigned long)(uintptr_t)input_ptr, STAI_NETWORK_IN_1_SIZE);
    printf("[OK] Output buffer @ 0x%08lX (%d floats)\r\n",
           (unsigned long)(uintptr_t)output_ptr, STAI_NETWORK_OUT_1_SIZE);

    /*========================================================================*/
    /*  Step 4: Set Input Data & Run Inference                               */
    /*========================================================================*/

    /* Copy example input data into the network input buffer */
    memcpy((void *)input_ptr, input_data, sizeof(input_data));

    printf("\r\n--- Inference ---\r\n");
    print_float_array("Input", input_ptr, STAI_NETWORK_IN_1_SIZE);

    /* Run synchronously (mode is ignored; always blocking) */
    ret = stai_network_run(network, 0);
    if (ret != STAI_SUCCESS) {
        printf("[ERROR] stai_network_run failed! return_code = %d\r\n", ret);
        goto error_halt;
    }

    printf("[OK] Inference completed successfully!\r\n");
    print_float_array("Output", output_ptr, STAI_NETWORK_OUT_1_SIZE);

    /*========================================================================*/
    /*  Step 5: Run again with different input to verify repeatability        */
    /*========================================================================*/
    {
        float input_data_2[STAI_NETWORK_IN_1_SIZE] = { 0.5f, 1.5f, 2.5f, 3.5f };

        memcpy((void *)input_ptr, input_data_2, sizeof(input_data_2));

        printf("\r\n--- Second Inference (different input) ---\r\n");
        print_float_array("Input", input_ptr, STAI_NETWORK_IN_1_SIZE);

        ret = stai_network_run(network, 0);
        if (ret != STAI_SUCCESS) {
            printf("[ERROR] Second inference failed! return_code = %d\r\n", ret);
            goto error_halt;
        }

        printf("[OK] Second inference completed!\r\n");
        print_float_array("Output", output_ptr, STAI_NETWORK_OUT_1_SIZE);
    }

    /*========================================================================*/
    /*  Done                                                                 */
    /*========================================================================*/
    printf("\r\nAll inferences completed successfully. Halting.\r\n");
    goto idle_loop;

error_halt:
    printf("\r\n[FATAL] Halting due to error.\r\n");

idle_loop:
    /* Loop forever */
    for (;;) {
        __asm volatile("nop");
    }
}

#if defined(__ARMCC_VERSION) && (__ARMCC_VERSION >= 6010050)
/* For ARM Compiler: ensure SystemInit is exported */
void SystemInit(void);
#endif