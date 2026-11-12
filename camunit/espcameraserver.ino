#include "secrets.h" // Copy secrets.h.example to this ignored local file.
#include "esp_camera.h"
#include "WiFi.h"
#include "esp_http_server.h"
#include "esp_timer.h"
#include "esp_system.h" // Include for esp_task_wdt_* functions
#include "esp_task_wdt.h" // Include for task watchdog functions

// 🔹 Wi-Fi credentials
const char* ssid = TRAINCAM_WIFI_SSID;
const char* password = TRAINCAM_WIFI_PASSWORD;

// 🔹 ESP32-S3 Pin Configuration
#define PWDN_GPIO_NUM  -1
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM  10
#define SIOD_GPIO_NUM  40
#define SIOC_GPIO_NUM  39

#define Y9_GPIO_NUM    48
#define Y8_GPIO_NUM    11
#define Y7_GPIO_NUM    12
#define Y6_GPIO_NUM    14
#define Y5_GPIO_NUM    16
#define Y4_GPIO_NUM    18
#define Y3_GPIO_NUM    17
#define Y2_GPIO_NUM    15
#define VSYNC_GPIO_NUM 38
#define HREF_GPIO_NUM  47
#define PCLK_GPIO_NUM  13

// 📷 Stream settings
#define STREAM_QUALITY 4  
#define STREAM_WIDTH   640 
#define STREAM_HEIGHT  480 

httpd_handle_t camera_httpd = NULL;
TaskHandle_t StreamTask;
camera_config_t config;
volatile int activeClients = 0;
volatile int frameCaptureFailures = 0;
volatile int wifiReconnectAttempts = 0;
unsigned long bootTime;
unsigned long lastConsoleLogTime = 0;

// 🔹 Restart Confirmation Code
const char* restart_code = "ncngrr";

// 📶 Wi-Fi Reconnect Parameters
const int MAX_WIFI_RECONNECT_ATTEMPTS = 30;
const int WIFI_RECONNECT_DELAY_MS = 5000;

// ⚙️ Configuration Parameters
#define CONFIG_FILE "/config.txt"

// 🚀 Camera Initialization
void startCamera() {
    Serial.println("📷 Initializing camera...");
    
    config.ledc_channel = LEDC_CHANNEL_0;
    config.ledc_timer = LEDC_TIMER_0;
    config.pin_d0 = Y2_GPIO_NUM;
    config.pin_d1 = Y3_GPIO_NUM;
    config.pin_d2 = Y4_GPIO_NUM;
    config.pin_d3 = Y5_GPIO_NUM;
    config.pin_d4 = Y6_GPIO_NUM;
    config.pin_d5 = Y7_GPIO_NUM;
    config.pin_d6 = Y8_GPIO_NUM;
    config.pin_d7 = Y9_GPIO_NUM;
    config.pin_xclk = XCLK_GPIO_NUM;
    config.pin_pclk = PCLK_GPIO_NUM;
    config.pin_vsync = VSYNC_GPIO_NUM;
    config.pin_href = HREF_GPIO_NUM;
    config.pin_sscb_sda = SIOD_GPIO_NUM;
    config.pin_sscb_scl = SIOC_GPIO_NUM;
    config.pin_pwdn = PWDN_GPIO_NUM;
    config.pin_reset = RESET_GPIO_NUM;
    config.xclk_freq_hz = 20000000;
    config.pixel_format = PIXFORMAT_JPEG;
    
    if (psramFound()) {
        Serial.println("✅ PSRAM detected! Using high-performance mode.");
        config.frame_size = FRAMESIZE_SVGA;  
        config.jpeg_quality = STREAM_QUALITY;
        config.fb_count = 2;
        Serial.println("📷 Camera initialized in high-performance mode.");
        // Display settings of the camera
        Serial.printf("📷 Camera settings: %dx%d, JPEG quality: %d, Frame count: %d\n", 
                      config.frame_size, config.jpeg_quality, config.fb_count);
    } else {
        Serial.println("❌ No PSRAM! Using fallback settings.");
        config.frame_size = FRAMESIZE_QVGA;
        config.jpeg_quality = STREAM_QUALITY + 2;
        config.fb_count = 1;
        Serial.println("📷 Camera initialized in fallback mode.");
        // Display settings of the camera
        Serial.printf("📷 Camera settings: %dx%d, JPEG quality: %d, Frame count: %d\n", 
                      config.frame_size, config.jpeg_quality, config.fb_count);
    }

    config.fb_location = CAMERA_FB_IN_PSRAM;
    config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;

    if (esp_camera_init(&config) == ESP_OK) {
        Serial.println("✅ Camera initialized!");
    } else {
        Serial.println("❌ Camera init failed! Restarting ESP...");
        log_e("Camera init failed!"); // Enhanced logging
        ESP.restart();
    }
}

// 📡 Wi-Fi Connection with Auto-Reconnect
void connectWiFi() {
    WiFi.mode(WIFI_STA);
    WiFi.begin(ssid, password);
    WiFi.setTxPower(WIFI_POWER_19_5dBm);
    WiFi.setSleep(false);
    
    Serial.print("📶 Connecting to WiFi...");
    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < MAX_WIFI_RECONNECT_ATTEMPTS) {
        delay(500);
        Serial.print(".");
        attempts++;
    }
    if (WiFi.status() == WL_CONNECTED) {
        Serial.println("\n✅ WiFi connected!");
        Serial.print("📡 IP Address: ");
        Serial.println(WiFi.localIP());
    } else {
        Serial.println("\n❌ Failed to connect to WiFi. Restarting...");
        log_e("Failed to connect to WiFi after multiple attempts.");
        ESP.restart();
    }
}

// 🔄 Reconnect Wi-Fi if Disconnected with Exponential Backoff
void checkWiFi() {
    if (WiFi.status() != WL_CONNECTED) {
        wifiReconnectAttempts++;
        Serial.print("⚠️ WiFi lost! Reconnecting (Attempt ");
        Serial.print(wifiReconnectAttempts);
        Serial.print(" of ");
        Serial.print(MAX_WIFI_RECONNECT_ATTEMPTS);
        Serial.println(")...");
        
        WiFi.disconnect();
        delay(100); // Small delay before reconnecting
        WiFi.reconnect();

        // Exponential backoff delay
        int delayMs = WIFI_RECONNECT_DELAY_MS * wifiReconnectAttempts;
        if (delayMs > 60000) delayMs = 60000; // Limit delay to 60 seconds

        Serial.print("   Waiting ");
        Serial.print(delayMs / 1000.0, 1);
        Serial.println(" seconds before next attempt.");
        delay(delayMs);

        if (wifiReconnectAttempts >= MAX_WIFI_RECONNECT_ATTEMPTS) {
            Serial.println("❌ Max WiFi reconnect attempts reached. Restarting...");
            log_e("Max WiFi reconnect attempts reached. Restarting.");
            ESP.restart();
        }
    }
}

// 📷 Capture Frame with PSRAM Optimization
camera_fb_t *safeCapture() {
    camera_fb_t *fb = esp_camera_fb_get();
    if (!fb) {
        frameCaptureFailures++;
        Serial.println("❌ Frame capture failed! Restarting camera...");
        log_e("Frame capture failed!");
        esp_camera_deinit();
        delay(500);
        esp_camera_init(&config);
        return NULL;
    }
    return fb;
}

// 🖥️ MJPEG Stream Handler
esp_err_t streamHandler(httpd_req_t *req) {
    Serial.println("📷 Starting video stream...");
    delay(2000);
    camera_fb_t *fb = NULL;
    char buffer[128];
    int r;

    httpd_resp_set_type(req, "multipart/x-mixed-replace;boundary=boundary");

    while (true) {
        fb = safeCapture();
        if (!fb) {
            delay(10); // Reduced delay
            continue;
        }

        int len = snprintf(buffer, sizeof(buffer),
            "\r\n--boundary\r\n"
            "Content-Type: image/jpeg\r\n"
            "Content-Length: %u\r\n"
            "X-Timestamp: %u.%03u\r\n\r\n", 
            fb->len, millis() / 1000, millis() % 1000);

        // Check if client is still connected
        r = httpd_req_recv(req, buffer, 0);
        if (r < 0) {
            Serial.println("⚠️ Client Disconnected! Closing stream.");
            esp_camera_fb_return(fb);
            break;
        }

        if (httpd_resp_send_chunk(req, buffer, len) != ESP_OK ||
            httpd_resp_send_chunk(req, (const char*)fb->buf, fb->len) != ESP_OK ||
            httpd_resp_send_chunk(req, "\r\n", 2) != ESP_OK) {
            Serial.println("⚠️ Client Disconnected! Closing stream.");
            esp_camera_fb_return(fb);
            break;
        }
        
        esp_camera_fb_return(fb);
        delay(1); // Add a small delay to free up resources
    }
    return ESP_OK;
}

// 📊 HTTP Status Endpoint in Separate Task
void statusTask(void *pvParameters) {
    Serial.println("📊 Status Task started."); // Debug print
    while (true) {
        if (camera_httpd != NULL) {
            // Use httpd_get_client_list to get the number of clients
            size_t max_clients = 4; // Maximum number of clients supported by the server
            int *client_list = (int *)malloc(sizeof(int) * max_clients);
            if (client_list == NULL) {
                Serial.println("❌ Failed to allocate memory for client list!");
                log_e("Failed to allocate memory for client list!");
            } else {
                esp_err_t ret = httpd_get_client_list(camera_httpd, &max_clients, client_list);
                if (ret == ESP_OK) {
                    size_t client_count = 0;
                    for (int i = 0; i < max_clients; i++) {
                        if (client_list[i] != -1) {
                            client_count++;
                        }
                    }
                    activeClients = client_count; // Update activeClients variable
                    Serial.printf("📊 Status: Clients: %d, Free Heap: %d, Uptime: %lu sec, Frame Failures: %d, Wi-Fi Reconnects: %d\n",
                                  client_count, ESP.getFreeHeap(), (millis() - bootTime) / 1000, frameCaptureFailures, wifiReconnectAttempts);
                } else {
                    Serial.println("❌ Failed to get client list!");
                    log_e("Failed to get client list!");
                }
                free(client_list);
            }
        } else {
            Serial.println("⚠️ HTTP Server not yet started.");
        }
        vTaskDelay(pdMS_TO_TICKS(60000));  // Every 60 sec
        esp_task_wdt_reset(); // Reset the watchdog timer
    }
}

// 📡 Start HTTP Servers
void startServers() {
    // Start the camera stream server
    httpd_config_t stream_config = HTTPD_DEFAULT_CONFIG();
    stream_config.task_priority = tskIDLE_PRIORITY + 5;
    stream_config.stack_size = 8192;
    stream_config.max_open_sockets = 4;
    stream_config.max_uri_handlers = 12;
    stream_config.lru_purge_enable = true;
    stream_config.recv_wait_timeout = 15;
    stream_config.send_wait_timeout = 15;

    httpd_uri_t stream_uri = { .uri = "/stream", .method = HTTP_GET, .handler = streamHandler };

    if (httpd_start(&camera_httpd, &stream_config) == ESP_OK) {
        httpd_register_uri_handler(camera_httpd, &stream_uri);
        Serial.println("✅ Stream HTTP Server Started");
    }

    xTaskCreatePinnedToCore(statusTask, "StatusTask", 4096, NULL, 1, NULL, 0);
    Serial.println("📊 Status Task created."); // Debug print
}

// 🐶 Initialize Watchdog Timer
void initWatchdog() {
    esp_task_wdt_config_t wdt_config = {
        .timeout_ms = 60000, // 60 second timeout
        .trigger_panic = false
    };
    esp_task_wdt_init(&wdt_config); // Initialize WDT with config
    esp_task_wdt_add(NULL); // Add current thread to WDT watch
}

// 🚀 Main Setup
void setup() {
    Serial.begin(115200);
    bootTime = millis();

    Serial.println("🚀 Starting ESP32-S3 Camera System...");
    Serial.println("🔹 Initializing Watchdog Timer...");
    initWatchdog();
    Serial.println("🔹 Initializing Camera...");
    startCamera();
    Serial.println("🔹 Connecting to WiFi...");
    connectWiFi();
    Serial.println("🔹 Starting HTTP Servers...");
    startServers(); // Start both servers
    Serial.println("✅ System Initialization Complete!");
}

// 🔄 Periodic Tasks
void loop() {
    checkWiFi();
    esp_task_wdt_reset(); // Reset the watchdog timer in the main loop
    delay(100); // Small delay to prevent starving other tasks
}
