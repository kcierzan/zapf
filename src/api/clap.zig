const std = @import("std");
const c = @cImport({
    @cInclude("clap/clap.h");
});

// TODO: re-export the string constants in plugin-features.h

pub const Version = c.clap_version_t;
pub const Plugin = c.clap_plugin_t;
pub const PluginDescriptor = c.clap_plugin_descriptor_t;
pub const PluginEntry = c.clap_plugin_entry_t;
pub const PluginFactory = c.clap_plugin_factory_t;
pub const Host = c.clap_host_t;
pub const Process = c.clap_process_t;
pub const AudioBuffer = c.clap_audio_buffer_t;
pub const EventHeader = c.clap_event_header_t;
pub const InputEvents = c.clap_input_events_t;
pub const OutputEvents = c.clap_output_events_t;
pub const UniversalPluginId = c.clap_universal_plugin_id_t;
pub const EventParam = c.clap_event_param_value_t;
pub const EventMod = c.clap_event_param_mod_t;
pub const EventNote = c.clap_event_note_t;
pub const EventNoteExpression = c.clap_event_note_expression_t;
pub const EventTransport = c.clap_event_transport_t;
pub const EventMidi = c.clap_event_midi_t;
pub const EventMidi2 = c.clap_event_midi2_t;
pub const EventMidiSysex = c.clap_event_midi_sysex_t;

pub const CORE_EVENT_SPACE_ID = c.CLAP_CORE_EVENT_SPACE_ID;
pub const Id = u32;
pub const INVALID_ID = std.math.maxInt(u32);

pub const EventFlags = struct {
    pub const EVENT_IS_LIVE = c.CLAP_EVENT_IS_LIVE;
    pub const EVENT_DONT_RECORD = c.CLAP_EVENT_DONT_RECORD;
};

pub const Event = struct {
    pub const EVENT_NOTE_ON = c.CLAP_EVENT_NOTE_ON;
    pub const EVENT_NOTE_OFF = c.CLAP_EVENT_NOTE_OFF;
    pub const EVENT_NOTE_CHOKE = c.CLAP_EVENT_NOTE_CHOKE;
    pub const EVENT_NOTE_END = c.CLAP_EVENT_NOTE_END;
    pub const EVENT_NOTE_EXPRESSION = c.CLAP_EVENT_NOTE_EXPRESSION;
    pub const EVENT_PARAM_VALUE = c.CLAP_EVENT_PARAM_VALUE;
    pub const EVENT_PARAM_MOD = c.CLAP_EVENT_PARAM_MOD;
    pub const EVENT_PARAM_GESTURE_BEGIN = c.CLAP_EVENT_PARAM_GESTURE_BEGIN;
    pub const EVENT_PARAM_GESTURE_END = c.CLAP_EVENT_PARAM_GESTURE_END;
    pub const EVENT_TRANSPORT = c.CLAP_EVENT_TRANSPORT;
    pub const EVENT_MIDI = c.CLAP_EVENT_MIDI;
    pub const EVENT_MIDI_SYSEX = c.CLAP_EVENT_MIDI_SYSEX;
    pub const EVENT_MIDI2 = c.CLAP_EVENT_MIDI2;
};

pub const NoteExpression = struct {
    pub const VOLUME = c.CLAP_NOTE_EXPRESSION_VOLUME;
    pub const PAN = c.CLAP_NOTE_EXPRESSION_PAN;
    pub const TUNING = c.CLAP_NOTE_EXPRESSION_TUNING;
    pub const VIBRATO = c.CLAP_NOTE_EXPRESSION_VIBRATO;
    pub const EXPRESSION = c.CLAP_NOTE_EXPRESSION_EXPRESSION;
    pub const BRIGHTNESS = c.CLAP_NOTE_EXPRESSION_BRIGHTNESS;
    pub const PRESSURE = c.CLAP_NOTE_EXPRESSION_PRESSURE;
};

pub const ProcessStatus = struct {
    pub const ERROR = c.CLAP_PROCESS_ERROR;
    pub const CONTINUE = c.CLAP_PROCESS_CONTINUE;
    pub const CONTINUE_IF_NOT_QUIET = c.CLAP_PROCESS_CONTINUE_IF_NOT_QUIET;
    pub const TAIL = c.CLAP_PROCESS_TAIL;
    pub const SLEEP = c.CLAP_PROCESS_SLEEP;
};

pub const PluginFeatures = struct {
    pub const INSTRUMENT = c.CLAP_PLUGIN_FEATURE_INSTRUMENT;
    pub const AUDIO_EFFECT = c.CLAP_PLUGIN_FEATURE_AUDIO_EFFECT;
    pub const NOTE_EFFECT = c.CLAP_PLUGIN_FEATURE_NOTE_EFFECT;
    pub const NOTE_DETECTOR = c.CLAP_PLUGIN_FEATURE_NOTE_DETECTOR;
    pub const ANALYZER = c.CLAP_PLUGIN_FEATURE_ANALYZER;

    pub const SYNTHESIZER = "synthesizer";
    pub const SAMPLER = "sampler";
    pub const DRUM = "drum";
    pub const DRUM_MACHINE = "drum-machine";

    pub const FILTER = "filter";
    pub const PHASER = "phaser";
    pub const EQUALIZER = "equalizer";
    pub const DEESSER = "de-esser";
    pub const PHASE_VOCODER = "phase-vocoder";
    pub const GRANULAR = "granular";
    pub const FREQUENCY_SHIFTER = "frequency-shifter";
    pub const PITCH_SHIFTER = "pitch-shifter";

    pub const DISTORTION = "distortion";
    pub const TRANSIENT_SHAPER = "transient-shaper";
    pub const COMPRESSOR = "compressor";
    pub const EXPANDER = "expander";
    pub const GATE = "gate";
    pub const LIMITER = "limiter";

    pub const FLANGER = "flanger";
    pub const CHORUS = "chorus";
    pub const DELAY = "delay";
    pub const REVERB = "reverb";

    pub const TREMOLO = "tremolo";
    pub const GLITCH = "glitch";

    pub const UTILITY = "utility";
    pub const PITCH_CORRECTION = "pitch-correction";
    pub const RESTORATION = "restoration";

    pub const MULTI_EFFECTS = "multi-effects";

    pub const MIXING = "mixing";
    pub const MASTERING = "mastering";

    pub const MONO = "mono";
    pub const STEREO = "stereo";
    pub const SURROUND = "surround";
    pub const AMBISONIC = "ambisonic";
};
