#include <ncurses.h>
#include <iostream>
#include <fstream>
#include <unistd.h>
#include <nvml.h>
#include <ctime>
#include <vector>
#include <chrono>
#include <thread>

#define CHECK_NVML(result, message)                                           \
    if (result != NVML_SUCCESS)                                               \
    {                                                                         \
        endwin();                                                             \
        std::cerr << message << ": " << nvmlErrorString(result) << std::endl; \
        exit(1);                                                              \
    }

int main()
{
    // Initialize ncurses and colors
    initscr();
    noecho();
    curs_set(FALSE);
    start_color();
    init_pair(1, COLOR_RED,   COLOR_BLACK);   // TX in red
    init_pair(2, COLOR_GREEN, COLOR_BLACK);     // RX in green

    // Initialize NVML
    CHECK_NVML(nvmlInit(), "Failed to initialize NVML");

    unsigned int device_count;
    CHECK_NVML(nvmlDeviceGetCount(&device_count), "Failed to get device count");

    if (device_count == 0)
    {
        endwin();
        std::cerr << "No NVIDIA devices found." << std::endl;
        return 1;
    }

    // Open file for logging data
    std::ofstream outfile("bandwidth_data.txt");
    if (!outfile.is_open())
    {
        endwin();
        std::cerr << "Failed to open output file!" << std::endl;
        return 1;
    }

    // Get handle for the first device (adjust if needed)
    nvmlDevice_t device;
    CHECK_NVML(nvmlDeviceGetHandleByIndex(0, &device), "Failed to get device handle");

    // Get terminal dimensions
    int term_height, term_width;
    getmaxyx(stdscr, term_height, term_width);

    // Define the graph area (reserve space for y-axis labels and header/footer)
    const int graph_x_offset = 8;  // left margin for labels
    int plot_width  = term_width - graph_x_offset;
    int plot_height = term_height - 3; // header and footer rows

    // Sliding window buffers: one value per column of the plot area
    std::vector<unsigned int> tx_values(plot_width, 0);
    std::vector<unsigned int> rx_values(plot_width, 0);

    // Define maximum throughput (in KB/s) for scaling (adjust as needed)
    const unsigned int max_throughput = 30000;

    while (true)
    {
        // Fetch throughput values from NVML
        unsigned int tx_throughput, rx_throughput;
        CHECK_NVML(nvmlDeviceGetPcieThroughput(device, NVML_PCIE_UTIL_TX_BYTES, &tx_throughput),
                   "Failed to get PCIe TX throughput");
        CHECK_NVML(nvmlDeviceGetPcieThroughput(device, NVML_PCIE_UTIL_RX_BYTES, &rx_throughput),
                   "Failed to get PCIe RX throughput");

        // Log data with timestamp to file
        std::time_t now = std::time(0);
        char timestamp[20];
        std::strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", std::localtime(&now));
        outfile << timestamp << "," << tx_throughput << "," << rx_throughput << std::endl;

        // Update sliding window buffers: remove the oldest and append the new values
        tx_values.erase(tx_values.begin());
        rx_values.erase(rx_values.begin());
        tx_values.push_back(tx_throughput);
        rx_values.push_back(rx_throughput);

        // Clear the screen for redrawing
        clear();

        // Draw header
        mvprintw(0, 0, "PCIe Throughput Graph (TX in RED, RX in GREEN)");

        // Draw Y-axis labels on the left side
        for (int i = 0; i <= plot_height; i++)
        {
            double frac = (double)i / plot_height;
            unsigned int value = max_throughput - (unsigned int)(frac * max_throughput);
            mvprintw(i + 1, 0, "%5u|", value);
        }

        // Plot discrete points: one point per sample without connecting lines
        for (int x = 0; x < plot_width; x++)
        {
            int tx_row = 1 + (int)(((double)(max_throughput - tx_values[x]) / max_throughput) * plot_height);
            int rx_row = 1 + (int)(((double)(max_throughput - rx_values[x]) / max_throughput) * plot_height);

            attron(COLOR_PAIR(1));
            mvaddch(tx_row, x + graph_x_offset, '*');
            attroff(COLOR_PAIR(1));

            attron(COLOR_PAIR(2));
            mvaddch(rx_row, x + graph_x_offset, '+');
            attroff(COLOR_PAIR(2));
        }

        // Draw footer with the latest readings
        mvprintw(term_height - 1, 0, "Latest: TX = %u KB/s, RX = %u KB/s", tx_throughput, rx_throughput);

        // Refresh the screen to update the display
        refresh();

        // Short delay before the next update
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }

    // Cleanup (unreachable in this infinite loop but good practice)
    outfile.close();
    nvmlShutdown();
    endwin();
    return 0;
}
