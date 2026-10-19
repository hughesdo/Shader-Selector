#define BG_MODE 1        // 0 = white   1 = black   2 = chroma green
#define NODES 40         // thread count
#define HUBS 4           // convergence points
#define SEGS 16          // segments per thread
#define MOTES 100         // free-floating specks
#define ABERRATION 1     // global RGB split on every hit
#define BASS_SPLIT 1     // RGB split on SOME strings, only on the biggest bass hits
#define SPLIT_SHARE 0.5  // fraction of strings that split
#define SPLIT_PX 5.5     // channel separation in pixels
#define SEED 3.0         // random seed
#define ROT_SPEED 2.0    // scene rotation multiplier
#define LEVEL_BOOST 0.15

// ---- Buffer B row map (derived, so SEGS is a single knob) ----
#define BUF_W    512              // buffer columns; must be <= canvas width. Caps NODES+HUBS and MOTES.
#define ROW_PT0    3              // thread rows 0,1,2 = AABB / wc,hue,e / gr2,splitV
#define ROW_NODE (ROW_PT0 + SEGS + 1)   // 2 rows: q,radii,hue / splitV,hue
#define ROW_MOTE (ROW_NODE + 2)         // 2 rows: q,radii,r / hue
#define ROW_END  (ROW_MOTE + 2)