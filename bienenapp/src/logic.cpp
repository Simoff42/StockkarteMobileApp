// src/logic.cpp
#include "logic.h"
#include <string>
#include "httplib.h"
#include <iostream>
#include <android/log.h>
#include <nlohmann/json.hpp>
#include <future>
#include <chrono>

#define LOG_TAG "BienenApp_CPP"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

using json = nlohmann::json;

struct HttpResponse
{
    std::string status;
    std::string body;
};

// GOLBAL VARIABLES

std::string SESSION_ID;
unsigned val = 0;

HttpResponse post_request(const std::string &url, const std::string &body)
{
    LOGI("Preparing to send POST request to %s with body: %s", url.c_str(), body.c_str());

    // Wrap the entire network instantiation and request in an async worker thread
    // We capture 'url' and 'body' by value so the thread has its own safe copies.
    auto async_call = std::async(std::launch::async, [url, body]()
                                 {
        // Instantiate the client inside the thread. 
        // This ensures that if the main thread times out and returns early, 
        // the background thread still safely owns the client memory and won't crash.
        // httplib::Client cli("192.168.1.140", 8080);
        httplib::Client cli("10.5.177.29", 8080);
        
        cli.set_address_family(AF_INET);
        cli.set_keep_alive(false);
        cli.set_connection_timeout(5, 0);
        cli.set_read_timeout(5, 0);
        cli.set_write_timeout(5, 0);
        
        LOGI("HTTP client initialized inside async worker with base URL: http://10.5.48.95 :8080");
        
        // This is the blocking call that might hang infinitely
        return cli.Post(url.c_str(), body, "application/json"); });

    // Enforce a strict 6-second "hard timeout" (1 second longer than your socket timeout)
    auto status = async_call.wait_for(std::chrono::seconds(6));

    if (status == std::future_status::timeout)
    {
        // If we hit this, the OS-level socket completely deadlocked and ignored the httplib timeouts.
        LOGE("CRITICAL: Hard timeout reached! The C++ socket completely locked up.");
        return {"ERROR", "TIMEOUT"};
    }

    // If we get here, the call finished within the 6 seconds. Extract the result.
    auto res = async_call.get();

    LOGI("Sent POST request to %s with body: %s", url.c_str(), body.c_str());
    if (!res)
    {
        LOGE("Request failed with error code: %d", static_cast<int>(res.error()));
        return {"ERROR", "NETWORK_ERROR"};
    }

    LOGI("Received response: %d", res->status);

    switch (res->status)
    {
    case 200:
    case 201:
        return {"SUCCESS", res->body};
    case 400:
        LOGE("Bad request: %s", res->body.c_str());
        return {"ERROR", "BAD_REQUEST"};
    case 401:
        LOGE("Unauthorized");
        return {"ERROR", "UNAUTHORIZED"};
    case 404:
        LOGE("Endpoint not found: %s", url.c_str());
        return {"ERROR", "NOT_FOUND"};
    case 500:
        LOGE("Internal server error");
        return {"ERROR", "INTERNAL_SERVER_ERROR"};
    default:
        LOGE("HTTP error %d: %s", res->status, res->body.c_str());
        return {"ERROR", "HTTP_ERROR"};
    }

    return HttpResponse{"ERROR", "UNKNOWN_ERROR"};
}

json parse_response_body(const std::string &body)
{
    try
    {
        return json::parse(body);
    }
    catch (const json::exception &e)
    {
        LOGE("JSON parse error: %s", e.what());
        return json::object();
    }
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

extern "C" __attribute__((visibility("default"))) __attribute__((used)) const char *
login(const char *username, const char *password)
{
    std::string body = "{\"username\": \"" + std::string(username) + "\", \"password\": \"" + std::string(password) + "\"}";
    HttpResponse response = post_request("/login/", body);
    LOGI("Login response: %s", response.body.c_str());

    if (response.status != "SUCCESS")
    {
        LOGE("Login failed with status: %s", response.body.c_str());
        return strdup(response.body.c_str());
    }
    else
    {
        json response_json = parse_response_body(response.body);
        if (response_json["status"] == "SUCCESS" && response_json.contains("sessionId"))
        {
            SESSION_ID = response_json["sessionId"].get<std::string>();
            LOGI("Login successful! Session ID: %s", SESSION_ID.c_str());
        }
        else
        {
            LOGE("Login failed: %s", response.body.c_str());
        }
        if (response_json.contains("status") && response_json["status"].is_string())
        {
            return strdup(response_json["status"].get<std::string>().c_str());
        }
        else
        {
            return strdup("UNKNOWN");
        }
    }
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) const char *logout()
{
    std::string body = "{\"sessionId\": \"" + SESSION_ID + "\"}";
    HttpResponse response = post_request("/logout/", body);
    LOGI("Logout response: %s", response.body.c_str());
    SESSION_ID = "";

    return strdup(parse_response_body(response.body).value("status", "UNKNOWN").c_str());
}

// Homescreen overview of hives for the logged in user

// Globals
json HIVES_OVERVIEW;

extern "C" __attribute__((visibility("default"))) __attribute__((used)) const char *load_hives_overview()
{
    std::string body = "{\"sessionId\": \"" + SESSION_ID + "\"}";
    HttpResponse response = post_request("/getUserHivesOverview/", body);
    LOGI("Hives overview response: %s", response.body.c_str());

    if (response.status != "SUCCESS")
    {
        LOGE("Failed to load hives overview with status: %s", response.body.c_str());
        return strdup(response.body.c_str());
    }
    else
    {
        // save to a global variable for later use in hive details screen
        HIVES_OVERVIEW = parse_response_body(response.body);

        return strdup(response.status.c_str());
    }
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) const char *get_hives_overview_json()
{
    std::string body = "{\"sessionId\": \"" + SESSION_ID + "\"}";
    HttpResponse response = post_request("/getUserHivesOverview/", body);
    LOGI("Hives overview response: %s", response.body.c_str());

    if (response.status != "SUCCESS")
    {
        LOGE("Failed to load hives overview with status: %s", response.body.c_str());
        return strdup(response.body.c_str());
    }
    else
    {
        // save to a global variable for later use in hive details screen
        HIVES_OVERVIEW = parse_response_body(response.body);
    }
    std::string overview_str = HIVES_OVERVIEW.dump();
    LOGI("Returning hives overview JSON: %s", overview_str.c_str());
    return strdup(overview_str.c_str());
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) const char *get_hive_details_json(int hive_id)
{
    std::string body = "{\"sessionId\": \"" + SESSION_ID + "\", \"hiveId\": " + std::to_string(hive_id) + "}";
    HttpResponse response = post_request("/getHiveDetails/", body);
    LOGI("Hive details response: %s", response.body.c_str());

    if (response.status != "SUCCESS")
    {
        LOGE("Failed to load hive details with status: %s", response.body.c_str());
        return strdup(response.body.c_str());
    }
    else
    {
        return strdup(response.body.c_str());
    }
}