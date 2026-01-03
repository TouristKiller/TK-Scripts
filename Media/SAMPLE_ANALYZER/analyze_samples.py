#!/usr/bin/env python3
r"""
TK Sample Analyzer - Audio Classification Tool
Analyzes audio samples and exports a JSON database for TK Media Browser

Usage:
    python analyze_samples.py <sample_folder> [output.json]
    
Example:
    python analyze_samples.py "D:\Samples\Drums" sample_database.json
"""

import os
import sys
import json
import argparse
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import warnings

warnings.filterwarnings('ignore')

try:
    import numpy as np
except ImportError:
    print("ERROR: numpy not installed. Run: pip install numpy")
    sys.exit(1)

try:
    import librosa
except ImportError:
    print("ERROR: librosa not installed. Run: pip install librosa")
    sys.exit(1)

import math

def sanitize_for_json(obj):
    """Recursively replace NaN and Infinity values with None for valid JSON output"""
    if isinstance(obj, dict):
        return {k: sanitize_for_json(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [sanitize_for_json(item) for item in obj]
    elif isinstance(obj, float):
        if math.isnan(obj) or math.isinf(obj):
            return None
        return obj
    return obj


class SampleAnalyzer:
    
    SUPPORTED_EXTENSIONS = {'.wav', '.mp3', '.aif', '.aiff', '.flac', '.ogg', '.m4a'}
    
    DRUM_KEYWORDS = {
        'kick': ['kick', 'bass drum', 'bassdrum', 'bd_', '_bd', ' bd '],
        'snare': ['snare', 'snr_', '_snr', ' snr ', 'clap', 'rimshot', 'rim shot'],
        'hihat': ['hihat', 'hi-hat', 'hi hat', 'hh_', '_hh', ' hh ', 'closed hat', 'open hat', 'pedal hat',
                  'closedhat', 'openhat', 'closehat', 'hat_', '_hat', 'hats', 'closed_', 'open_'],
        'tom': ['tom_', '_tom', ' tom ', 'floor tom', 'rack tom'],
        'cymbal': ['cymbal', 'crash', 'ride', 'splash', 'china'],
        'percussion': ['perc', 'shaker', 'tambourine', 'conga', 'bongo', 'cowbell', 
                       'woodblock', 'triangle', 'cabasa', 'guiro', 'maracas'],
        'drumloop': ['drum loop', 'drumloop', 'drum_loop', 'drums_loop', 'drum loops', 
                     'beat_', '_beat', 'breakbeat', 'break beat', 'break_beat',
                     'drum break', 'top loop', 'toploop', 'top_loop', 'full loop',
                     'drum groove', 'full_drums', 'full drums', 'full_drum', 
                     'drums_lps', 'drum_lps', 'drumlps', 'drumslps',
                     '_drums_', 'all_drums', 'drum_full', 'drums_full']
    }
    
    DRUMLOOP_FOLDER_KEYWORDS = ['drums_lps', 'drum_lps', 'drumlps', 'full_drums', 'drum loops',
                                'drum_loops', 'drumloops', 'beats', 'breakbeats', 'breaks']
    
    OTHER_KEYWORDS = {
        'bass': ['bass', 'sub_', '_sub', ' sub ', '808 bass', 'synth bass', 'reese'],
        'synth': ['synth', 'lead_', '_lead', ' lead ', 'pluck', 'arp_', '_arp', ' arp ', 'stab'],
        'pad': ['pad_', '_pad', ' pad ', 'ambient', 'atmosphere', 'drone', 'texture'],
        'keys': ['piano', 'pno', 'keys', 'organ', 'rhodes', 'wurli', 'electric piano', 'epiano', 'e_piano'],
        'guitar': ['guitar', 'gtr', 'grt', 'gtrs', 'grts', 'elec_gtr', 'elec_grt', 'elec gtr', 'elec grt',
                   'acoustic guitar', 'electric guitar', 'elec guitar', 'dist_', '_dist',
                   'acousticguitar', 'electricguitar', 'strat', 'telecaster', 'les paul', 'nylon'],
        'fx': ['_fx_', 'fx_', '_fx', ' fx ', 'sfx_', '_sfx', ' sfx ',
               'riser', 'risers', 'sweep', 'sweeps', 'downlifter', 'uplifter',
               'whoosh', 'woosh', 'swoosh', 'swell', 'swells',
               'impact', 'impacts', 'transition', 'transitions',
               'buildup', 'build-up', 'build_up', 'buildups',
               'foley', 'white noise', 'pink noise', 'noise_',
               'laser', 'zap', 'glitch', 'stutter', 'reverse_', '_reverse',
               'sub drop', 'subdrop', 'sub_drop'],
        'vocal': ['vocal', 'vox', 'voice', 'acapella', 'choir', 'spoken'],
        'strings': ['strings', 'violin', 'viola', 'cello', 'orchestra'],
        'loop': ['loop', 'groove', 'pattern', 'phrase', 'riff']
    }
    
    ONESHOT_KEYWORDS = ['oneshot', 'one-shot', 'one shot', 'single hit', 'single_']
    LOOP_KEYWORDS = ['loop', 'beat', 'groove', 'pattern', 'breakbeat', 'drumloop', 
                    'toploop', 'phrase', 'riff', 'sequence', 'rhythm', 'backing',
                    'arp loop', 'synth loop', 'bass loop', 'melody', 'hook', 'motif']
    
    def __init__(self, sample_folder, verbose=True):
        self.sample_folder = Path(sample_folder)
        self.verbose = verbose
        self.results = []
        self.errors = []
        
    def log(self, message):
        if self.verbose:
            print(message)
    
    def keyword_match(self, keyword, text):
        import re
        if len(keyword) <= 3:
            pattern = r'(?:^|[\s_\-\.])' + re.escape(keyword) + r'(?:$|[\s_\-\.])'
            return bool(re.search(pattern, text))
        else:
            return keyword in text
    
    def guess_category_from_path(self, filepath):
        path_lower = str(filepath).lower()
        filename_lower = filepath.name.lower()
        
        for category, keywords in self.DRUM_KEYWORDS.items():
            for kw in keywords:
                if self.keyword_match(kw, filename_lower) or self.keyword_match(kw, path_lower):
                    return category, True
        
        for category, keywords in self.OTHER_KEYWORDS.items():
            for kw in keywords:
                if self.keyword_match(kw, filename_lower) or self.keyword_match(kw, path_lower):
                    return category, False
        
        return None, None
    
    def analyze_spectral_features(self, y, sr):
        spectral_centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr))
        spectral_rolloff = np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr))
        spectral_bandwidth = np.mean(librosa.feature.spectral_bandwidth(y=y, sr=sr))
        zero_crossings = np.mean(librosa.feature.zero_crossing_rate(y=y))
        rms = np.mean(librosa.feature.rms(y=y))
        
        return {
            'spectral_centroid': float(spectral_centroid),
            'spectral_rolloff': float(spectral_rolloff),
            'spectral_bandwidth': float(spectral_bandwidth),
            'zero_crossings': float(zero_crossings),
            'rms': float(rms)
        }
    
    def detect_onsets(self, y, sr):
        onset_env = librosa.onset.onset_strength(y=y, sr=sr)
        onsets = librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr)
        return len(onsets), onset_env
    
    def estimate_tempo(self, y, sr, onset_env=None):
        try:
            if onset_env is None:
                onset_env = librosa.onset.onset_strength(y=y, sr=sr)
            tempo, _ = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr)
            if isinstance(tempo, np.ndarray):
                tempo = tempo[0] if len(tempo) > 0 else 0
            return float(tempo) if tempo > 0 else None
        except:
            return None
    
    def estimate_pitch(self, y, sr):
        try:
            pitches, magnitudes = librosa.piptrack(y=y, sr=sr, fmin=30, fmax=2000)
            
            pitch_values = []
            for t in range(pitches.shape[1]):
                index = magnitudes[:, t].argmax()
                pitch = pitches[index, t]
                if pitch > 0:
                    pitch_values.append(pitch)
            
            if pitch_values:
                median_pitch = np.median(pitch_values)
                confidence = len(pitch_values) / pitches.shape[1]
                return float(median_pitch), confidence
            return None, 0
        except:
            return None, 0
    
    def hz_to_note(self, hz):
        if not hz or hz <= 0:
            return None
        notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        c0 = 16.35
        try:
            half_steps = 12 * np.log2(hz / c0)
            note_index = int(round(half_steps)) % 12
            octave = int(half_steps // 12)
            if 0 <= octave <= 9:
                return f"{notes[note_index]}{octave}"
        except:
            pass
        return None
    
    def extract_bpm_from_name(self, filepath):
        import re
        filename = filepath.stem
        folder = filepath.parent.name
        
        patterns = [
            r'[\._\-\s](\d{2,3})[\s_]?bpm',
            r'bpm[\s_]?(\d{2,3})',
            r'_(\d{2,3})$',
            r'[\._\-\s](\d{2,3})[\._\-\s]',
            r'^(\d{2,3})[\._\-\s]',
            r'[\._\-](\d{2,3})[\._\-]',
            r'\[(\d{2,3})\]',
            r'\((\d{2,3})\)',
        ]
        
        for text in [filename, folder]:
            for pattern in patterns:
                match = re.search(pattern, text, re.IGNORECASE)
                if match:
                    bpm = int(match.group(1))
                    if 60 <= bpm <= 200:
                        return bpm
        return None
    
    def extract_key_from_name(self, filepath):
        import re
        filename = filepath.stem
        folder = filepath.parent.name
        
        notes = ['C', 'D', 'E', 'F', 'G', 'A', 'B']
        accidentals = ['#', 'b', 'sharp', 'flat', '']
        modes = ['m', 'min', 'minor', 'maj', 'major', '']
        
        patterns = [
            r'[\s_\-\.]([A-Ga-g][#b]?)\s?(m|min|minor|maj|major)?[\s_\-\.]',
            r'[\s_\-\.]([A-Ga-g])\s?(sharp|flat)?\s?(m|min|minor|maj|major)?[\s_\-\.]',
            r'^([A-Ga-g][#b]?)\s?(m|min|minor|maj|major)?[\s_\-\.]',
            r'[\s_\-\.]key[\s_\-\.]?([A-Ga-g][#b]?)\s?(m|min|minor)?',
            r'[\s_\-\.]([A-Ga-g][#b]?[0-9])[\s_\-\.]',
        ]
        
        for text in [filename, folder]:
            for pattern in patterns:
                match = re.search(pattern, text, re.IGNORECASE)
                if match:
                    note = match.group(1).upper()
                    
                    if len(note) >= 2 and note[-1].isdigit():
                        return note
                    
                    if len(note) == 1 or (len(note) == 2 and note[1] in '#b'):
                        mode = ''
                        if match.lastindex >= 2 and match.group(2):
                            mode_str = match.group(2).lower()
                            if mode_str in ['m', 'min', 'minor']:
                                mode = 'm'
                        
                        if len(note) == 2:
                            note = note[0] + note[1].lower()
                        
                        return note + mode if mode else note
        
        return None
    
    def key_to_hz(self, key_str):
        if not key_str:
            return None
        
        import re
        match = re.match(r'^([A-Ga-g][#b]?)(\d)?', key_str)
        if not match:
            return None
        
        note = match.group(1).upper()
        octave = int(match.group(2)) if match.group(2) else 4
        
        note_offsets = {
            'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3,
            'E': 4, 'F': 5, 'F#': 6, 'Gb': 6, 'G': 7, 'G#': 8, 
            'Ab': 8, 'A': 9, 'A#': 10, 'Bb': 10, 'B': 11
        }
        
        if len(note) == 2 and note[1] == 'B':
            note = note[0] + 'b'
        
        if note not in note_offsets:
            return None
        
        midi_note = (octave + 1) * 12 + note_offsets[note]
        hz = 440.0 * (2 ** ((midi_note - 69) / 12.0))
        return hz
    
    def detect_loop_from_name(self, filepath):
        path_lower = str(filepath).lower()
        filename_lower = filepath.name.lower()
        
        for kw in self.LOOP_KEYWORDS:
            if kw in filename_lower or kw in path_lower:
                return True
        
        for kw in self.ONESHOT_KEYWORDS:
            if kw in filename_lower or kw in path_lower:
                return False
        
        return None
    
    def detect_loop_from_audio(self, duration, onset_count, onset_env, tempo, sr):
        if duration < 0.5:
            return False
        
        if duration > 3.0 and onset_count >= 4:
            return True
        
        if duration > 1.5 and onset_count >= 4:
            if tempo and 50 <= tempo <= 200:
                try:
                    intervals = np.diff(librosa.onset.onset_detect(
                        onset_envelope=onset_env, sr=sr, units='time'))
                    if len(intervals) >= 2:
                        interval_std = np.std(intervals)
                        interval_mean = np.mean(intervals)
                        if interval_mean > 0.05 and interval_std / interval_mean < 0.6:
                            return True
                except:
                    pass
        
        if duration > 2.0 and onset_count >= 6:
            return True, 0.75
            
        return False, 0.2
    
    def extract_features(self, y, sr):
        spectral_centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr))
        spectral_rolloff = np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr))
        spectral_bandwidth = np.mean(librosa.feature.spectral_bandwidth(y=y, sr=sr))
        zero_crossings = np.mean(librosa.feature.zero_crossing_rate(y=y))
        rms = np.mean(librosa.feature.rms(y=y))
        
        spectral_flatness = np.mean(librosa.feature.spectral_flatness(y=y))
        spectral_contrast = librosa.feature.spectral_contrast(y=y, sr=sr)
        spectral_contrast_mean = np.mean(spectral_contrast, axis=1)
        
        peak_amplitude = np.max(np.abs(y))
        rms_amplitude = np.sqrt(np.mean(y**2))
        crest_factor = peak_amplitude / rms_amplitude if rms_amplitude > 0 else 0
        crest_factor_db = 20 * np.log10(crest_factor) if crest_factor > 0 else 0
        
        brightness = spectral_centroid / (sr / 2) if sr > 0 else 0
        
        try:
            harmonic, percussive = librosa.effects.hpss(y)
            harmonic_energy = np.sum(harmonic**2)
            total_energy = np.sum(y**2)
            harmonicity = harmonic_energy / total_energy if total_energy > 0 else 0
        except:
            harmonicity = 0.5
        
        noisiness = float(spectral_flatness)
        
        mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13)
        mfcc_mean = np.mean(mfcc, axis=1)
        mfcc_std = np.std(mfcc, axis=1)
        
        chroma = librosa.feature.chroma_stft(y=y, sr=sr)
        chroma_mean = np.mean(chroma, axis=1)
        
        rms_envelope = librosa.feature.rms(y=y)[0]
        rms_mean = np.mean(rms_envelope)
        rms_std = np.std(rms_envelope)
        
        if len(rms_envelope) > 1:
            rms_normalized = rms_envelope / np.max(rms_envelope) if np.max(rms_envelope) > 0 else rms_envelope
            amplitude_envelope = rms_normalized.tolist()
        else:
            amplitude_envelope = [1.0]
        
        envelope = np.abs(y)
        frame_length = min(512, len(envelope) // 10) if len(envelope) > 512 else len(envelope)
        if frame_length > 0:
            envelope_smoothed = np.convolve(envelope, np.ones(frame_length)/frame_length, mode='valid')
            if len(envelope_smoothed) > 0:
                peak_idx = np.argmax(envelope_smoothed)
                attack_samples = peak_idx
                attack_slope = envelope_smoothed[peak_idx] / (attack_samples / sr) if attack_samples > 0 else 0
                attack_time = attack_samples / sr
                
                decay_part = envelope_smoothed[peak_idx:]
                if len(decay_part) > 1:
                    decay_rate = (decay_part[0] - decay_part[-1]) / (len(decay_part) / sr)
                    
                    threshold = decay_part[0] * 0.1
                    decay_indices = np.where(decay_part < threshold)[0]
                    if len(decay_indices) > 0:
                        decay_time = decay_indices[0] / sr
                    else:
                        decay_time = len(decay_part) / sr
                else:
                    decay_rate = 0
                    decay_time = 0
            else:
                attack_slope = 0
                attack_time = 0
                decay_rate = 0
                decay_time = 0
        else:
            attack_slope = 0
            attack_time = 0
            decay_rate = 0
            decay_time = 0
        
        duration = librosa.get_duration(y=y, sr=sr)
        onset_env = librosa.onset.onset_strength(y=y, sr=sr)
        onsets = librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr)
        onset_count = len(onsets)
        
        try:
            tempo, _ = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr)
            if isinstance(tempo, np.ndarray):
                tempo = tempo[0] if len(tempo) > 0 else 0
            tempo = float(tempo) if tempo > 0 else None
        except:
            tempo = None
        
        try:
            pitches, magnitudes = librosa.piptrack(y=y, sr=sr, fmin=30, fmax=2000)
            pitch_values = []
            for t in range(pitches.shape[1]):
                index = magnitudes[:, t].argmax()
                pitch = pitches[index, t]
                if pitch > 0:
                    pitch_values.append(pitch)
            if pitch_values:
                pitch_hz = float(np.median(pitch_values))
                pitch_confidence = len(pitch_values) / pitches.shape[1]
            else:
                pitch_hz = None
                pitch_confidence = 0
        except:
            pitch_hz = None
            pitch_confidence = 0
        
        feature_vector = np.concatenate([
            [brightness, harmonicity, noisiness, crest_factor],
            [spectral_centroid / 10000, spectral_rolloff / 20000, spectral_bandwidth / 5000],
            [attack_time * 10, decay_time],
            mfcc_mean / 100,
            chroma_mean
        ])
        feature_vector = feature_vector / (np.linalg.norm(feature_vector) + 1e-8)
        
        return {
            'spectral_centroid': float(spectral_centroid),
            'spectral_rolloff': float(spectral_rolloff),
            'spectral_bandwidth': float(spectral_bandwidth),
            'spectral_flatness': float(spectral_flatness),
            'spectral_contrast': spectral_contrast_mean.tolist(),
            'zero_crossings': float(zero_crossings),
            'rms': float(rms),
            'peak_amplitude': float(peak_amplitude),
            'crest_factor': float(crest_factor),
            'crest_factor_db': float(crest_factor_db),
            'brightness': float(brightness),
            'harmonicity': float(harmonicity),
            'noisiness': float(noisiness),
            'mfcc_mean': mfcc_mean,
            'mfcc_std': mfcc_std,
            'chroma_mean': chroma_mean.tolist(),
            'rms_mean': float(rms_mean),
            'rms_std': float(rms_std),
            'amplitude_envelope': amplitude_envelope[:20],
            'attack_slope': float(attack_slope),
            'attack_time': float(attack_time),
            'decay_rate': float(decay_rate),
            'decay_time': float(decay_time),
            'duration': duration,
            'onset_count': onset_count,
            'onset_env': onset_env,
            'tempo': tempo,
            'pitch_hz': pitch_hz,
            'pitch_confidence': pitch_confidence,
            'feature_vector': feature_vector.tolist()
        }
    
    def get_keyword_scores(self, filepath):
        import re
        scores = {}
        all_categories = list(self.DRUM_KEYWORDS.keys()) + list(self.OTHER_KEYWORDS.keys())
        for cat in all_categories:
            scores[cat] = 0.0
        
        filename_lower = filepath.name.lower()
        path_lower = str(filepath.parent).lower()
        full_path_lower = str(filepath).lower()
        
        def check_match(keyword, text):
            if len(keyword) <= 3:
                pattern = r'(?:^|[\s_\-\.])' + re.escape(keyword) + r'(?:$|[\s_\-\.])'
                return bool(re.search(pattern, text))
            return keyword in text
        
        for category, keywords in self.DRUM_KEYWORDS.items():
            for kw in keywords:
                if check_match(kw, filename_lower):
                    scores[category] += 1.0
                elif check_match(kw, path_lower):
                    scores[category] += 0.5
        
        for category, keywords in self.OTHER_KEYWORDS.items():
            for kw in keywords:
                if check_match(kw, filename_lower):
                    scores[category] += 1.0
                elif check_match(kw, path_lower):
                    scores[category] += 0.5
        
        for kw in self.DRUMLOOP_FOLDER_KEYWORDS:
            if kw in path_lower:
                scores['drumloop'] += 1.5
                break
        
        if scores['drumloop'] < 0.5:
            if ('drum' in path_lower or 'drums' in path_lower) and ('loop' in path_lower or 'lps' in path_lower):
                scores['drumloop'] += 1.2
            elif 'full_drums' in full_path_lower or 'full drums' in full_path_lower:
                scores['drumloop'] += 1.5
        
        return scores
    
    def get_audio_scores(self, features):
        scores = {}
        all_categories = list(self.DRUM_KEYWORDS.keys()) + list(self.OTHER_KEYWORDS.keys())
        for cat in all_categories:
            scores[cat] = 0.0
        
        sc = features['spectral_centroid']
        sr = features['spectral_rolloff']
        sb = features['spectral_bandwidth']
        rms = features['rms']
        zc = features['zero_crossings']
        dur = features['duration']
        onset_count = features['onset_count']
        attack = features['attack_slope']
        decay = features['decay_rate']
        pitch_conf = features['pitch_confidence']
        
        brightness = features.get('brightness', sc / 11025)
        harmonicity = features.get('harmonicity', 0.5)
        noisiness = features.get('noisiness', 0.5)
        crest_factor = features.get('crest_factor', 3.0)
        attack_time = features.get('attack_time', 0.01)
        
        is_tonal = harmonicity > 0.6 or pitch_conf > 0.5
        is_noisy = noisiness > 0.3 or harmonicity < 0.3
        is_percussive = crest_factor > 6 and attack_time < 0.02
        is_very_short = dur < 0.3
        is_short = dur < 0.8
        is_medium = 0.8 <= dur < 2.0
        is_long = dur >= 2.0
        
        if sc < 600 and is_short and not is_tonal and is_percussive:
            scores['kick'] += 1.2
        if sc < 300 and attack > 10:
            scores['kick'] += 0.5
        if rms > 0.15 and sc < 800 and harmonicity < 0.4:
            scores['kick'] += 0.4
        if crest_factor > 8 and sc < 500:
            scores['kick'] += 0.3
        
        if 1200 < sc < 4000 and is_short and is_noisy and is_percussive:
            scores['snare'] += 1.2
        if attack > 5 and 1000 < sc < 4500 and noisiness > 0.2:
            scores['snare'] += 0.4
        if sb > 2000 and is_very_short and crest_factor > 5:
            scores['snare'] += 0.3
        
        if sc > 3500 and is_short and is_noisy:
            scores['hihat'] += 1.0
        if sc > 5000 and noisiness > 0.4:
            scores['hihat'] += 0.6
        if zc > 0.15 and brightness > 0.5:
            scores['hihat'] += 0.3
        if not is_tonal and sc > 4000 and is_very_short:
            scores['hihat'] += 0.5
        
        if sc > 5000 and is_medium and noisiness > 0.3:
            scores['cymbal'] += 1.0
        if decay < 0.5 and sc > 4000 and dur > 0.5:
            scores['cymbal'] += 0.4
        if brightness > 0.6 and harmonicity < 0.4 and is_medium:
            scores['cymbal'] += 0.3
        
        if not is_tonal and is_short and 600 < sc < 3000 and is_percussive:
            scores['percussion'] += 0.6
        if 2 <= onset_count <= 5 and is_short and crest_factor > 4:
            scores['percussion'] += 0.3
        
        if sc > 800 and sc < 2500 and is_short and not is_tonal:
            scores['tom'] += 0.5
        if attack > 3 and sc < 2000 and harmonicity < 0.5:
            scores['tom'] += 0.3
        
        if sc < 500 and is_tonal and harmonicity > 0.5:
            scores['bass'] += 1.2
        if sc < 300 and brightness < 0.1:
            scores['bass'] += 0.4
        if pitch_conf > 0.7 and sc < 600:
            scores['bass'] += 0.3
        
        if is_tonal and is_medium and harmonicity > 0.5:
            scores['synth'] += 0.6
        if is_tonal and 1000 < sc < 4000 and noisiness < 0.2:
            scores['synth'] += 0.3
        if is_tonal and not is_long and attack > 2:
            scores['synth'] += 0.2
        
        if is_tonal and is_long and attack_time > 0.1 and harmonicity > 0.6:
            scores['pad'] += 1.2
        if rms < 0.08 and is_long and features['rms_std'] < 0.03:
            scores['pad'] += 0.4
        if harmonicity > 0.7 and dur > 2.0:
            scores['pad'] += 0.3
        
        if is_tonal and 300 < sc < 2000 and is_medium and harmonicity > 0.6:
            scores['keys'] += 0.6
        if attack_time < 0.05 and is_tonal and 400 < sc < 3000:
            scores['keys'] += 0.3
        
        if is_tonal and 1500 < sc < 5000 and dur > 0.3:
            scores['guitar'] += 0.5
        if is_tonal and sb > 2000 and sb < 6000 and dur > 0.5 and harmonicity > 0.4:
            scores['guitar'] += 0.4
        if features['mfcc_mean'][2] > 10 and is_tonal and dur > 0.3:
            scores['guitar'] += 0.2
        
        if dur > 1.0 and onset_count >= 4 and not is_tonal:
            scores['drumloop'] += 0.8
        if dur > 1.5 and onset_count >= 6 and sc > 1000 and sc < 6000:
            scores['drumloop'] += 0.5
        if dur > 2.0 and features['rms_std'] > 0.03 and not is_tonal:
            scores['drumloop'] += 0.3
        
        if is_long and noisiness > 0.3 and onset_count < 3:
            scores['fx'] += 0.8
        if attack_time > 0.5 and is_long:
            scores['fx'] += 0.5
        if dur > 1.0 and harmonicity < 0.3 and onset_count < 4:
            scores['fx'] += 0.4
        if brightness > 0.5 and dur > 1.0 and not is_tonal:
            scores['fx'] += 0.3
        
        return scores
    
    def ensemble_classify(self, filepath, features):
        keyword_scores = self.get_keyword_scores(filepath)
        audio_scores = self.get_audio_scores(features)
        
        combined = {}
        all_categories = set(keyword_scores.keys()) | set(audio_scores.keys())
        
        keyword_weight = 3.0
        audio_weight = 1.0
        
        for cat in all_categories:
            kw_score = keyword_scores.get(cat, 0)
            au_score = audio_scores.get(cat, 0)
            combined[cat] = (kw_score * keyword_weight) + (au_score * audio_weight)
        
        specific_categories = ['guitar', 'vocal', 'fx', 'keys', 'strings', 'bass']
        ambiguous_categories = ['pad', 'synth', 'loop']
        
        for specific_cat in specific_categories:
            if keyword_scores.get(specific_cat, 0) >= 1.0:
                for ambig_cat in ambiguous_categories:
                    if combined.get(ambig_cat, 0) > 0:
                        combined[ambig_cat] *= 0.3
        
        sorted_cats = sorted(combined.items(), key=lambda x: -x[1])
        best_category = sorted_cats[0][0]
        best_score = sorted_cats[0][1]
        
        secondary_categories = []
        if len(sorted_cats) > 1:
            threshold = best_score * 0.6
            for cat, score in sorted_cats[1:4]:
                if score >= threshold and score >= 0.5:
                    secondary_categories.append(cat)
        
        if best_score < 0.3:
            sc = features['spectral_centroid']
            dur = features['duration']
            is_tonal = features['pitch_confidence'] > 0.5
            
            if dur < 0.5 and not is_tonal:
                best_category = 'percussion'
            elif is_tonal:
                best_category = 'synth'
            else:
                best_category = 'other'
        
        is_drum = best_category in self.DRUM_KEYWORDS
        confidence = min(best_score / 3.0, 1.0)
        
        return best_category, is_drum, confidence, secondary_categories
    
    def detect_loop_from_audio_new(self, features):
        duration = features['duration']
        onset_count = features['onset_count']
        tempo = features['tempo']
        onset_env = features['onset_env']
        sr = 22050
        
        if duration < 0.5:
            return False, 0.9
        
        if duration > 3.0 and onset_count >= 4:
            return True, 0.85
        
        if duration > 1.5 and onset_count >= 4:
            if tempo and 50 <= tempo <= 200:
                try:
                    intervals = np.diff(librosa.onset.onset_detect(
                        onset_envelope=onset_env, sr=sr, units='time'))
                    if len(intervals) >= 2:
                        interval_std = np.std(intervals)
                        interval_mean = np.mean(intervals)
                        if interval_mean > 0.05 and interval_std / interval_mean < 0.6:
                            return True, 0.8
                except:
                    pass
        
        if duration > 2.0 and onset_count >= 6:
            return True, 0.75
            
        return False, 0.2
    
    def classify_by_audio(self, features, duration, onset_count, pitch_confidence):
        sc = features['spectral_centroid']
        rms = features['rms']
        zc = features['zero_crossings']
        
        is_very_short = duration < 0.3
        is_short = duration < 0.8
        is_medium = 0.8 <= duration < 2.0
        is_long = duration >= 2.0
        is_tonal = pitch_confidence > 0.5
        has_sharp_attack = onset_count > 0 and onset_count < 4
        
        if not is_tonal and sc > 4000 and is_short:
            return "hihat", True
        
        if is_very_short and not is_tonal:
            if sc < 600:
                return "kick", True
            elif sc > 3000:
                return "hihat", True
            elif 1000 < sc < 3000:
                return "snare", True
            else:
                return "percussion", True
        
        if is_short and not is_tonal:
            if sc < 600:
                return "kick", True
            elif sc > 5000:
                return "cymbal", True
            elif 1000 < sc < 4000 and has_sharp_attack:
                return "snare", True
            elif sc > 3000:
                return "percussion", True
            else:
                return "percussion", True
        
        if is_medium:
            if not is_tonal and sc > 5000:
                return "cymbal", True
            if sc < 600 and is_tonal:
                return "bass", False
        
        if is_tonal:
            if sc < 500:
                return "bass", False
            elif is_long and rms < 0.1:
                return "pad", False
            elif is_long:
                return "synth", False
            else:
                return "synth", False
        
        if is_long and onset_count > 4:
            return "loop", False
        
        if is_long or (is_medium and not is_tonal):
            return "fx", False
        
        return "other", False
    
    def analyze_file(self, filepath):
        try:
            y, sr = librosa.load(filepath, sr=22050, mono=True, duration=30)
            
            features = self.extract_features(y, sr)
            
            category, is_drum, confidence, secondary_categories = self.ensemble_classify(filepath, features)
            
            subcategory = self.get_subcategory(category, features)
            
            name_loop = self.detect_loop_from_name(filepath)
            audio_loop, audio_loop_conf = self.detect_loop_from_audio_new(features)
            
            if name_loop == False:
                is_loop = False
            elif name_loop == True:
                is_loop = True
            elif audio_loop and audio_loop_conf > 0.6:
                is_loop = True
            else:
                is_loop = False
            
            tags = self.generate_tags(filepath, category, features, is_loop)
            
            for sec_cat in secondary_categories:
                if sec_cat not in tags:
                    tags.append(sec_cat)
            
            if features['rms'] > 0.15 and 'loud' not in tags:
                tags.append('loud')
            elif features['rms'] < 0.05 and 'soft' not in tags:
                tags.append('soft')
            
            if features['attack_slope'] > 10 and 'punchy' not in tags:
                tags.append('punchy')
            
            if features.get('attack_time', 0.02) < 0.005 and 'snappy' not in tags:
                tags.append('snappy')
            
            if features.get('decay_time', 0.1) > 0.5 and 'sustained' not in tags:
                tags.append('sustained')
            
            if features.get('harmonicity', 0.5) > 0.7 and 'tonal' not in tags:
                tags.append('tonal')
            
            sc = features['spectral_centroid']
            if 1000 < sc < 3000 and 'warm' not in tags:
                tags.append('warm')
            
            cf = features.get('crest_factor', 3.0)
            if cf < 2.0 and 'compressed' not in tags:
                tags.append('compressed')
            elif cf > 5.0 and 'dynamic' not in tags:
                tags.append('dynamic')
            
            bpm_from_name = self.extract_bpm_from_name(filepath)
            final_bpm = None
            if bpm_from_name:
                final_bpm = bpm_from_name
            elif is_loop and features['tempo'] and features['onset_count'] >= 4:
                audio_bpm = features['tempo']
                if 50 <= audio_bpm <= 200:
                    final_bpm = round(audio_bpm)
            
            key_from_name = self.extract_key_from_name(filepath)
            final_pitch_note = None
            final_pitch_hz = None
            
            if key_from_name:
                final_pitch_note = key_from_name
                final_pitch_hz = self.key_to_hz(key_from_name)
            elif features['pitch_hz'] and features['pitch_hz'] > 0:
                final_pitch_hz = features['pitch_hz']
                final_pitch_note = self.hz_to_note(features['pitch_hz'])
            
            return {
                "path": str(filepath),
                "name": filepath.name,
                "folder": str(filepath.parent.relative_to(self.sample_folder)) if filepath.parent != self.sample_folder else "",
                "category": category,
                "subcategory": subcategory,
                "secondary_categories": secondary_categories if secondary_categories else None,
                "is_drum": is_drum,
                "duration": round(features['duration'], 3),
                "is_loop": is_loop,
                "bpm": final_bpm,
                "pitch_hz": round(final_pitch_hz, 1) if final_pitch_hz else None,
                "pitch_note": final_pitch_note,
                "brightness": round(features.get('brightness', features['spectral_centroid'] / 11025), 3),
                "harmonicity": round(features.get('harmonicity', 0.5), 3),
                "noisiness": round(features.get('noisiness', 0.5), 3),
                "crest_factor": round(features.get('crest_factor', 3.0), 2),
                "crest_factor_db": round(features.get('crest_factor_db', 9.5), 1),
                "attack_time": round(features.get('attack_time', 0.01), 4),
                "decay_time": round(features.get('decay_time', 0.1), 4),
                "energy": round(features['rms'] * 100, 2),
                "peak_db": round(20 * np.log10(features.get('peak_amplitude', 0.5) + 1e-8), 1),
                "rms_db": round(20 * np.log10(features['rms'] + 1e-8), 1),
                "spectral_centroid": round(features['spectral_centroid'], 1),
                "spectral_rolloff": round(features['spectral_rolloff'], 1),
                "spectral_bandwidth": round(features['spectral_bandwidth'], 1),
                "onset_count": features['onset_count'],
                "confidence": round(confidence, 2),
                "tags": tags,
                "feature_vector": features.get('feature_vector', []),
                "chroma": features.get('chroma_mean', []),
                "mfcc": [round(m, 3) for m in features['mfcc_mean'].tolist()] if hasattr(features['mfcc_mean'], 'tolist') else features['mfcc_mean']
            }
            
        except Exception as e:
            self.errors.append({"path": str(filepath), "error": str(e)})
            return None
    
    def get_subcategory(self, category, features):
        sc = features['spectral_centroid']
        
        subcategories = {
            'kick': {
                'sub': lambda: sc < 200,
                'punchy': lambda: 200 <= sc < 500,
                'acoustic': lambda: sc >= 500
            },
            'snare': {
                'tight': lambda: sc > 3000,
                'fat': lambda: sc < 2000,
                'acoustic': lambda: 2000 <= sc <= 3000
            },
            'hihat': {
                'closed': lambda: features['rms'] > 0.1,
                'open': lambda: features['rms'] <= 0.1
            }
        }
        
        if category in subcategories:
            for subcat, condition in subcategories[category].items():
                if condition():
                    return subcat
        
        return None
    
    def generate_tags(self, filepath, category, features, is_loop):
        tags = [category]
        
        filename_lower = filepath.name.lower()
        path_lower = str(filepath).lower()
        
        tag_keywords = {
            '808': '808', '909': '909', 'analog': 'analog', 'digital': 'digital',
            'acoustic': 'acoustic', 'electronic': 'electronic', 'punchy': 'punchy',
            'soft': 'soft', 'hard': 'hard', 'tight': 'tight', 'fat': 'fat',
            'dry': 'dry', 'wet': 'wet', 'processed': 'processed', 'raw': 'raw',
            'vintage': 'vintage', 'modern': 'modern', 'lo-fi': 'lo-fi', 'lofi': 'lo-fi',
            'clean': 'clean', 'distorted': 'distorted', 'saturated': 'saturated'
        }
        
        for keyword, tag in tag_keywords.items():
            if keyword in filename_lower or keyword in path_lower:
                if tag not in tags:
                    tags.append(tag)
        
        if features['spectral_centroid'] > 5000:
            tags.append('bright')
        elif features['spectral_centroid'] < 1000:
            tags.append('dark')
        
        if features['rms'] > 0.15:
            tags.append('loud')
        elif features['rms'] < 0.05:
            tags.append('quiet')
        
        if is_loop:
            tags.append('loop')
        else:
            tags.append('one-shot')
        
        return tags
    
    def analyze_folder(self, max_workers=4):
        audio_files = []
        
        for ext in self.SUPPORTED_EXTENSIONS:
            audio_files.extend(self.sample_folder.rglob(f"*{ext}"))
            audio_files.extend(self.sample_folder.rglob(f"*{ext.upper()}"))
        
        audio_files = list(set(audio_files))
        total = len(audio_files)
        
        self.log(f"\n{'='*60}")
        self.log(f"TK Sample Analyzer")
        self.log(f"{'='*60}")
        self.log(f"Folder: {self.sample_folder}")
        self.log(f"Found {total} audio files to analyze...")
        self.log(f"{'='*60}\n")
        
        processed = 0
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_file = {executor.submit(self.analyze_file, f): f for f in audio_files}
            
            for future in as_completed(future_to_file):
                filepath = future_to_file[future]
                processed += 1
                
                try:
                    result = future.result()
                    if result:
                        self.results.append(result)
                        if self.verbose:
                            cat_display = f"[{result['category'].upper():10}]"
                            print(f"[{processed:5}/{total}] {cat_display} {result['name'][:50]}")
                except Exception as e:
                    self.errors.append({"path": str(filepath), "error": str(e)})
        
        self.log(f"\n{'='*60}")
        self.log(f"Analysis complete!")
        self.log(f"Processed: {len(self.results)} files")
        self.log(f"Errors: {len(self.errors)} files")
        self.log(f"{'='*60}\n")
        
        return self.results
    
    def get_category_summary(self):
        summary = {}
        drum_count = 0
        other_count = 0
        
        for sample in self.results:
            cat = sample["category"]
            summary[cat] = summary.get(cat, 0) + 1
            if sample.get("is_drum"):
                drum_count += 1
            else:
                other_count += 1
        
        return summary, drum_count, other_count
    
    def export_json(self, output_path):
        category_summary, drum_count, other_count = self.get_category_summary()
        
        data = {
            "version": "3.0",
            "analyzer": "TK Sample Analyzer CLI (Ensemble)",
            "sample_count": len(self.results),
            "drum_count": drum_count,
            "other_count": other_count,
            "root_folder": str(self.sample_folder),
            "categories": category_summary,
            "samples": self.results,
            "errors": self.errors if self.errors else None
        }
        
        data = sanitize_for_json(data)
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        
        self.log(f"Exported to: {output_path}")
        self.log(f"\nCategory breakdown:")
        for cat, count in sorted(category_summary.items(), key=lambda x: -x[1]):
            self.log(f"  {cat:15} : {count:5} samples")
        self.log(f"\n  {'DRUMS':15} : {drum_count:5} samples")
        self.log(f"  {'OTHER':15} : {other_count:5} samples")


def main():
    parser = argparse.ArgumentParser(
        description='TK Sample Analyzer - Analyze and categorize audio samples'
    )
    parser.add_argument('folder', help='Path to sample folder to analyze')
    parser.add_argument('output', nargs='?', default='sample_database.json',
                        help='Output JSON file (default: sample_database.json)')
    parser.add_argument('-w', '--workers', type=int, default=4,
                        help='Number of parallel workers (default: 4)')
    parser.add_argument('-q', '--quiet', action='store_true',
                        help='Quiet mode - minimal output')
    
    args = parser.parse_args()
    
    if not os.path.isdir(args.folder):
        print(f"ERROR: Folder not found: {args.folder}")
        sys.exit(1)
    
    analyzer = SampleAnalyzer(args.folder, verbose=not args.quiet)
    analyzer.analyze_folder(max_workers=args.workers)
    analyzer.export_json(args.output)
    
    print(f"\nDone! Database saved to: {args.output}")


if __name__ == "__main__":
    main()
