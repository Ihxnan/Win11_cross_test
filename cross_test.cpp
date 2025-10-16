#include <iostream>
#include <cstdlib>
#include <chrono>
#include <string>
#include <fstream>

using namespace std;
using namespace chrono;

bool executeCommand(const string& cmd) {
    return system(cmd.c_str()) == 0;
}

bool compileProgram(const string& source, const string& exe, const string& options = "") {
    cout << "Compiling " << source << "..." << flush;
    string cmd = "g++ " + options + " " + source + " -o " + exe;
    if (executeCommand(cmd)) {
        cout << "success" << endl;
        return true;
    }
    else {
        cout << "failed" << endl;
        return false;
    }
}

void displayFileContent(const string& filename) {
    ifstream file(filename);
    if (!file.is_open()) {
        cout << "Cannot open file: " << filename << endl;
        return;
    }

    cout << "[" << filename << " content:]:" << endl;
    string line;
    while (getline(file, line)) {
        cout << line << endl;
    }
    file.close();
}

void cleanExecutables() {
    executeCommand("del /q ans.exe test.exe data.exe");
    cout << "Executables cleaned up" << endl;
}

void fullCleanUp() {
    cleanExecutables();
    executeCommand("del /q data.txt test.txt ans.txt");
    cout << "All temporary files cleaned up" << endl;
}

bool runSingleTest() {
    if (!executeCommand("test.exe < data.txt > test.txt")) {
        cerr << "Test program execution failed" << endl;
        return false;
    }

    if (!executeCommand("ans.exe < data.txt > ans.txt")) {
        cerr << "Answer program execution failed" << endl;
        return false;
    }

    if (system("fc /b test.txt ans.txt > nul")) {
        cout << "Error!" << endl;
        cout << "The following files are preserved for debugging:" << endl;
        cout << "- Test data: data.txt" << endl;
        cout << "- Test program output: test.txt" << endl;
        cout << "- Answer program output: ans.txt" << endl;

        displayFileContent("test.txt");
        displayFileContent("ans.txt");
        return false;
    }

    return true;
}

int main() {
    bool allTestsPassed = false;

    try {
        if (!compileProgram("ans.cpp", "ans.exe", "-O2")) return 1;
        if (!compileProgram("test.cpp", "test.exe", "-O2")) return 1;
        if (!compileProgram("data.cpp", "data.exe", "-O2")) return 1;

        if (!executeCommand("data.exe > data.txt")) {
            cerr << "Test data generation failed" << endl;
            cleanExecutables();
            return 1;
        }

        const int TOTAL_TESTS = 101;

        if (!runSingleTest()) {
            cleanExecutables();
            return 1;
        }

        if (!executeCommand("data.exe > data.txt")) {
            cerr << "Test data generation failed" << endl;
            cleanExecutables();
            return 1;
        }

        for (int i = 1; i <= TOTAL_TESTS - 1; i++) {
            cout << "Test " << i << ": " << flush;

            auto start = high_resolution_clock::now();

            if (!runSingleTest()) {
                cleanExecutables();
                return 1;
            }

            auto end = high_resolution_clock::now();
            auto duration = duration_cast<milliseconds>(end - start);

            cout << "Passed, time taken " << duration.count() << "ms" << endl;

            if (i < TOTAL_TESTS - 1 && !executeCommand("data.exe > data.txt")) {
                cerr << "Test data generation failed" << endl;
                cleanExecutables();
                return 1;
            }
        }

        cout << "All " << TOTAL_TESTS - 1 << " tests passed!" << endl;
        allTestsPassed = true;
    }
    catch (...) {
        cerr << "Unknown error occurred" << endl;
    }

    if (allTestsPassed) {
        fullCleanUp();
    }
    else {
        cleanExecutables();
    }

    return 0;
}
