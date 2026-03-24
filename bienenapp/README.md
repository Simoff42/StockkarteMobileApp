# bienenapp

A new Flutter project.

## Compile and run

1. Run `flutter pub run ffigen` to compile Cpp-Dart bridge
2. Run `flutter run` to compile app in Debug mode

## compile for WEB

1. In the src directory, run:

emcc logic.cpp -o ../web/bridge.js \
 -I json/include \
 -s EXPORTED_FUNCTIONS="['_malloc', '_free', '_get_value', '_add_one', '_login', '_logout', '_get_hives_overview_json', '_get_hive_details_json', '_calculate_comb_history', '_submit_action']" \
 -s EXPORTED_RUNTIME_METHODS="['ccall', 'cwrap', 'UTF8ToString', 'stringToUTF8', 'lengthBytesUTF8']" \
 -O3
