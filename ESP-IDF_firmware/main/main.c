#include <stdio.h>
#include <math.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/i2c.h"
#include "driver/uart.h"
#include "esp_rom_sys.h"

#define I2C_MASTER_SCL_IO           8
#define I2C_MASTER_SDA_IO           10
#define I2C_MASTER_NUM              I2C_NUM_0
#define I2C_MASTER_FREQ_HZ          100000
#define I2C_MASTER_TX_BUF_DISABLE   0
#define I2C_MASTER_RX_BUF_DISABLE   0

#define FPGA_UART_NUM               UART_NUM_1
#define FPGA_UART_TX_PIN            4
#define FPGA_UART_BAUD_RATE         115200

#define SHTC3_ADDR                  0x70

#define SHTC3_CMD_WAKEUP            0x3517
#define SHTC3_CMD_SLEEP             0xB098
#define SHTC3_CMD_MEAS_T_CSE        0x609C
#define SHTC3_CMD_MEAS_RH_CSE       0x401A

static esp_err_t i2c_master_init(void) {
    i2c_config_t conf = {
        .mode = I2C_MODE_MASTER,
        .sda_io_num = I2C_MASTER_SDA_IO,
        .sda_pullup_en = GPIO_PULLUP_ENABLE,
        .scl_io_num = I2C_MASTER_SCL_IO,
        .scl_pullup_en = GPIO_PULLUP_ENABLE,
        .master.clk_speed = I2C_MASTER_FREQ_HZ,
    };
    esp_err_t ret = i2c_param_config(I2C_MASTER_NUM, &conf);
    if (ret != ESP_OK) return ret;
    return i2c_driver_install(I2C_MASTER_NUM, conf.mode, I2C_MASTER_RX_BUF_DISABLE, I2C_MASTER_TX_BUF_DISABLE, 0);
}

static esp_err_t fpga_uart_init(void) {
    uart_config_t uart_config = {
        .baud_rate  = FPGA_UART_BAUD_RATE,
        .data_bits  = UART_DATA_8_BITS,
        .parity     = UART_PARITY_DISABLE,
        .stop_bits  = UART_STOP_BITS_1,
        .flow_ctrl  = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };
    // 1. Configure parameters FIRST
    ESP_ERROR_CHECK(uart_param_config(FPGA_UART_NUM, &uart_config));
    // 2. Route TX to GPIO 4 SECOND (leave RX unrouted so floating pin doesn't glitch)
    ESP_ERROR_CHECK(uart_set_pin(FPGA_UART_NUM, FPGA_UART_TX_PIN, UART_PIN_NO_CHANGE,
                                 UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));
    // 3. Install driver THIRD
    return uart_driver_install(FPGA_UART_NUM, 256, 0, 0, NULL, 0);
}

static uint8_t shtc3_crc8(const uint8_t *data, size_t len) {
    uint8_t crc = 0xFF;
    for (size_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (uint8_t bit = 8; bit > 0; --bit) {
            if (crc & 0x80) {
                crc = (crc << 1) ^ 0x31;
            } else {
                crc = (crc << 1);
            }
        }
    }
    return crc;
}

static esp_err_t shtc3_send_cmd(uint16_t cmd) {
    uint8_t buf[2] = { (uint8_t)(cmd >> 8), (uint8_t)(cmd & 0xFF) };
    return i2c_master_write_to_device(I2C_MASTER_NUM, SHTC3_ADDR, buf, sizeof(buf), pdMS_TO_TICKS(100));
}

esp_err_t shtc3_wakeup(void) {
    esp_err_t ret = shtc3_send_cmd(SHTC3_CMD_WAKEUP);
    esp_rom_delay_us(300);
    return ret;
}

esp_err_t shtc3_sleep(void) {
    return shtc3_send_cmd(SHTC3_CMD_SLEEP);
}

esp_err_t read_temperature(float *temp_c, float *temp_f) {
    esp_err_t ret = shtc3_send_cmd(SHTC3_CMD_MEAS_T_CSE);
    if (ret != ESP_OK) return ret;

    vTaskDelay(pdMS_TO_TICKS(20));

    uint8_t rx[3];
    ret = i2c_master_read_from_device(I2C_MASTER_NUM, SHTC3_ADDR, rx, 3, pdMS_TO_TICKS(100));
    if (ret != ESP_OK) return ret;

    if (shtc3_crc8(rx, 2) != rx[2]) {
        return ESP_ERR_INVALID_CRC;
    }

    uint16_t raw = ((uint16_t)rx[0] << 8) | rx[1];
    *temp_c = -45.0f + 175.0f * ((float)raw / 65536.0f);
    *temp_f = (*temp_c * 1.8f) + 32.0f;
    return ESP_OK;
}

esp_err_t read_humidity(float *humidity) {
    esp_err_t ret = shtc3_send_cmd(SHTC3_CMD_MEAS_RH_CSE);
    if (ret != ESP_OK) return ret;

    vTaskDelay(pdMS_TO_TICKS(20));

    uint8_t rx[3];
    ret = i2c_master_read_from_device(I2C_MASTER_NUM, SHTC3_ADDR, rx, 3, pdMS_TO_TICKS(100));
    if (ret != ESP_OK) return ret;

    if (shtc3_crc8(rx, 2) != rx[2]) {
        return ESP_ERR_INVALID_CRC;
    }

    uint16_t raw = ((uint16_t)rx[0] << 8) | rx[1];
    *humidity = 100.0f * ((float)raw / 65536.0f);
    return ESP_OK;
}

void app_main(void) {
    ESP_ERROR_CHECK(i2c_master_init());
    ESP_ERROR_CHECK(fpga_uart_init());

    while (1) {
        shtc3_wakeup();

        float tc = 0.0f, tf = 0.0f, rh = 0.0f;
        esp_err_t err_t = read_temperature(&tc, &tf);
        esp_err_t err_rh = read_humidity(&rh);

        shtc3_sleep();

        if (err_t == ESP_OK && err_rh == ESP_OK) {
            uint8_t temp_byte = (uint8_t)roundf(tc);
            uart_write_bytes(FPGA_UART_NUM, (const char *)&temp_byte, 1);

            printf("Temperature: %uC (%.0fF) | Humidity: %.0f%% -> Sent 0x%02X to FPGA\n",
                   temp_byte, roundf(tf), roundf(rh), temp_byte);
        } else {
            printf("Sensor read failure: T=%s, RH=%s\n", 
                   esp_err_to_name(err_t), esp_err_to_name(err_rh));
        }

        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
