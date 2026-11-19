#pragma once
// S54 garden: a read-only viewer and sound of the S54 trial (two lives on the Pi).
// It reads only Mac-side files: experiments/s54-watch.tsv (hourly watch rows), experiments/trial-data/ref-*.sha
// (reference payload SHA per step) and experiments/trial-data/drives-669.txt (yields per step). It never contacts
// the Pi and never writes into the lab. Between watch rows the step n is an estimate (10 s per step from the last
// observed row); the hash used for the melody is the reference hash of that n (the trial matched it at every check).
#include "ofMain.h"
#include "ofxImGui.h"
#include "BodyView.h"
#include <array>
#include <mutex>

struct LifeObs {
    std::string unit = "?";
    long n = -1;
    std::string match = "-";
};

struct WatchRow {
    long epoch = 0;
    std::string time, boot, thr, ext4, fsState, fsErr;
    LifeObs life[2];
};

// piano voice from the MIS analysis: per partial a fast and a slow decay (two-stage), inharmonic partials, hammer noise
struct Voice {
    static const int P = 16;
    double phase[P] = {0}, inc[P] = {0}, a1[P] = {0}, a2[P] = {0}, d1[P] = {0}, d2[P] = {0};
    double env = 0, hammer = 0, hammerAmp = 0;
    bool dissonant = false;
};

// bronze church bell voice from the Naples recording (bell_tables.h, tools/analyze_bell.py): the measured partials
// (ratios to the prime), each with a fast stage (the strike, measured where it could be) and a slow stage (the ring;
// its decay is provisional), plus clapper noise
// Each partial is a doublet: a real bell is not perfectly round, so a partial splits into two close modes and the
// sound swells and fades slowly (the split per partial is provisional, not measured).
struct Bell {
    static const int P = 20; // = bell::P (checked in ofApp.cpp)
    double phase[P] = {0}, inc[P] = {0}, phase2[P] = {0}, inc2[P] = {0}, a1[P] = {0}, a2[P] = {0}, d1[P] = {0}, d2[P] = {0};
    double clap = 0, clapAmp = 0, t = 0, env = 0;
    bool beat = false;
};

// Freeverb (Jezar at Dreampoint, public domain): 8 parallel combs and 4 serial allpasses per channel
struct Reverb {
    struct Comb { std::vector<float> b; size_t i = 0; float store = 0; };
    struct Allpass { std::vector<float> b; size_t i = 0; };
    Comb comb[2][8];
    Allpass ap[2][4];
    float feedback = 0.92f, damp = 0.3f;
    void setup(double sr) {
        static const int ct[8] = {1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617}, at[4] = {556, 441, 341, 225};
        const double k = sr / 44100.0;
        for (int c = 0; c < 2; ++c) {
            for (int j = 0; j < 8; ++j) comb[c][j].b.assign((size_t)((ct[j] + 23 * c) * k), 0.0f);
            for (int j = 0; j < 4; ++j) ap[c][j].b.assign((size_t)((at[j] + 23 * c) * k), 0.0f);
        }
    }
    void process(float in, float out[2]) {
        for (int c = 0; c < 2; ++c) {
            float y = 0;
            for (auto &cb : comb[c]) {
                float o = cb.b[cb.i];
                cb.store = o * (1 - damp) + cb.store * damp;
                cb.b[cb.i] = in + cb.store * feedback;
                if (++cb.i >= cb.b.size()) cb.i = 0;
                y += o;
            }
            for (auto &a : ap[c]) {
                float bo = a.b[a.i];
                a.b[a.i] = y + bo * 0.5f;
                y = bo - y;
                if (++a.i >= a.b.size()) a.i = 0;
            }
            out[c] = y;
        }
    }
};

class ofApp : public ofBaseApp {
public:
    void setup() override;
    void update() override;
    void draw() override;
    void keyPressed(int key) override;
    void audioOut(ofSoundBuffer &buffer) override;

private:
    // data (ref and drives are read-only after setup, so the audio thread may read them)
    std::string lab;
    std::vector<std::array<uint8_t, 32>> ref[2];
    std::vector<std::array<int, 2>> drives;
    std::vector<WatchRow> rows;
    std::string firstBoot;
    int bootChanges = 0;
    std::time_t tsvMtime = 0;
    float lastReload = -100;
    long deadAt[2] = {20515, 11343};
    const char *lifeName[2] = {"trial-1  L2", "trial-2  L2+SF"};

    void drawHud(float hue[2]);
    void setupGui();
    void writeWav(const char *path);
    std::vector<float> rec;
    bool recording = false;
    float soloPiano = 1, soloBell = 1;
    float bellGain = 2.0f; // 2026-11-17: bell-only rms 0.0185 vs piano-only 0.061 (S54_SOLO, mean of L/R); 2.0 puts the bell near 0.6x the piano
    void loadRefs();
    void reloadTsv();

    // time
    bool demo = false;
    double demoWarp = 600.0, demoAnchorReal = 0, demoAnchorSim = 0;
    double simNow() const;

    // per-life view state (UI thread)
    double stepF[2] = {0, 0};
    float alive[2] = {1, 1};
    bool obsDead[2] = {false, false}, expDead[2] = {false, false}, mismatch[2] = {false, false};
    float flash = 0;
    float hueS[2] = {0.3f, 0.6f};
    bool stale = false, heat = false, fsBad = false, unreachable = false;
    bool hud = true;

    // shared with the audio thread
    std::mutex mtx;
    struct Params {
        double stepF[2] = {0, 0};
        double rate = 0.1; // steps per second
        float alive[2] = {1, 1};
        bool mismatch[2] = {false, false};
        bool stale = false, heat = false, fsBad = false;
        float volume = 0.6f;
        bool mute = false;
        bool reverb = true, binaural = false;
    } params;

    // audio thread state
    ofSoundStream stream;
    double sr = 48000;
    long lastSlot[2] = {-1, -1};
    Voice voices[2][6];
    Bell bells[2][2];
    int bellNext[2] = {0, 0};
    long lastStep[2] = {-1, -1};
    float clapLp[2] = {0, 0};
    double lfo = 0;
    float gainS[2] = {1, 1}, lp[2] = {0, 0}, lpCut = 1.0f;
    Reverb reverb;
    // binaural: each life is a source 35 degrees off centre; the far ear hears it later (spherical head, Woodworth)
    // and duller (head shadow as a shelf at 1.2 kHz). For headphones.
    std::vector<float> itdBuf[2];
    size_t itdPos = 0;
    float shadowLp[2] = {0, 0};
    float pulse[2] = {0, 0}; // written by the audio thread, read by UI (benign race on a float)
    uint32_t rng = 12345;
    float frand() { rng = rng * 1664525u + 1013904223u; return (rng >> 8) / 16777216.0f; }

    ofShader shader;
    ofFbo fbo;
    ofxImGui::Gui gui;
    ImFont *fontMain = nullptr, *fontTitle = nullptr, *fontMono = nullptr;
    BodyView view;
    bool panelOpen = true;
    float volumeUi = 0.6f;
    bool muteUi = false;
    bool reverbUi = true, binauralUi = false;
};
