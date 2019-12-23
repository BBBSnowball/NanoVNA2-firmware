#pragma once
#include "common.hpp"
#include <mculib/small_function.hpp>

#define OFFSETX 15
#define OFFSETY 0
#define WIDTH 291
#define HEIGHT 233
#define TRACES_MAX 4


#define CELLOFFSETX 5
#define AREA_WIDTH_NORMAL (WIDTH + CELLOFFSETX*2)

extern int area_width;
extern int area_height;

#define GRIDY 29

// this function is called to determine frequency in hz at a marker point
extern small_function<freqHz_t(int index)> plot_getFrequencyAt;

// this function is called periodically during plotting and can be used
// to process events in the event queue.
extern small_function<void()> plot_tick;

void plot_init(void);

// cancel ongoing draw operations further up the stack
void plot_cancel();
void update_grid(void);
void request_to_redraw_grid(void);
void redraw_frame(void);
//void redraw_all(void);
void request_to_draw_cells_behind_menu(void);
void request_to_draw_cells_behind_numeric_input(void);
void request_to_redraw_marker(int marker, int update_info);
void redraw_marker(int marker, int update_info);
void trace_get_info(int t, char *buf, int len);
void plot_into_index(complexf measured[2][SWEEP_POINTS_MAX]);
void force_set_markmap(void);
void draw_all(bool flush);
void draw_frequencies(void);
void draw_cal_status(void);

void markmap_all_markers(void);

void marker_position(int m, int t, int *x, int *y);
int search_nearest_index(int x, int y, int t);
