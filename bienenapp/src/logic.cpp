// src/logic.cpp
#include "logic.h"
#include <string>
#include "httplib.h"
#include <iostream>
#include <android/log.h>
// #include <bcrypt.h>

// Define a tag so you can easily filter your logs later
#define LOG_TAG "BienenApp_CPP"

// Create easy-to-use print macros (similar to printf)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

unsigned val = 0;

auto post_request(const std::string &url, const std::string &body)
{
    httplib::Client cli("http://10.5.62.55:8080");
    auto res = cli.Post(url.c_str(), body, "application/json");
    LOGI("Received response: %d", res->status);
    if (res && res->status == 200)
    {

        return res->body;
    }
    return std::string();
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
get_value()
{
    return val;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) void
add_one()
{
    val++;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) bool
login(const char *username, const char *password)
{
    // std::string hashed_password = bcrypt::generateHash(std::string(password));
    std::string body = "{\"username\": \"" + std::string(username) + "\", \"password\": \"" + std::string(password) + "\"}";
    std::string response = post_request("/login/", body);
    LOGI("Login response: %s", response.c_str());

    return response == "success";
}
