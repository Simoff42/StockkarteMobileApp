#include <stdint.h>
// #include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    // Add all the functions you want Flutter to see here!
    int get_value();
    void add_one();
    const char *login(const char *username, const char *password);
    const char *logout();
    const char *get_hives_overview_json();
    const char *get_hive_details_json(int hive_id);
    const char *calculate_comb_history(const char *logs_json, int current_b, int current_h);
    const char *submit_action(int hive_id, int volk_id, const char *action, const char *data_json);

#ifdef __cplusplus
}
#endif