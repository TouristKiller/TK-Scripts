#!/usr/bin/env python3
"""
TK Sample Analyzer - GUI Version
Incremental scanning: previously scanned samples are preserved
"""

import os
import sys
import json
import threading
import math
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from pathlib import Path
import atexit
from concurrent.futures import ThreadPoolExecutor, as_completed

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

SCRIPT_DIR = Path(__file__).parent
OUTPUT_FILE = SCRIPT_DIR.parent / "sample_database.json"
LOCK_FILE = SCRIPT_DIR / ".analyzer_lock"

def check_single_instance():
    if LOCK_FILE.exists():
        try:
            with open(LOCK_FILE, 'r') as f:
                pid = int(f.read().strip())
            
            process_running = False
            if sys.platform == 'win32':
                import subprocess
                result = subprocess.run(
                    ['tasklist', '/FI', f'PID eq {pid}', '/FO', 'CSV', '/NH'],
                    capture_output=True, text=True, creationflags=subprocess.CREATE_NO_WINDOW
                )
                process_running = str(pid) in result.stdout and 'python' in result.stdout.lower()
            else:
                try:
                    os.kill(pid, 0)
                    process_running = True
                except OSError:
                    process_running = False
            
            if process_running:
                root = tk.Tk()
                root.withdraw()
                result = messagebox.askyesno(
                    "TK Sample Analyzer",
                    "Another instance is already running.\n\n"
                    "Do you want to close the existing instance and open a new one?",
                    icon='question'
                )
                root.destroy()
                
                if result:
                    if sys.platform == 'win32':
                        subprocess.run(
                            ['taskkill', '/PID', str(pid), '/F'],
                            capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW
                        )
                    else:
                        try:
                            os.kill(pid, 9)
                        except:
                            pass
                    import time
                    time.sleep(0.5)
                else:
                    sys.exit(0)
                    
        except (ValueError, FileNotFoundError, PermissionError):
            pass
        except Exception:
            pass
    
    with open(LOCK_FILE, 'w') as f:
        f.write(str(os.getpid()))
    
    atexit.register(cleanup_lock)

def cleanup_lock():
    try:
        if LOCK_FILE.exists():
            LOCK_FILE.unlink()
    except:
        pass

class SampleAnalyzerGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("TK Sample Analyzer")
        self.root.geometry("480x480")
        self.root.resizable(True, True)
        
        try:
            self.root.iconbitmap(default='')
        except:
            pass
        
        self.existing_database = None
        self.existing_paths = set()
        self.scanned_root_folders = set()
        self.excluded_folders = set()
        self.folder_checkbuttons = {}
        self.setup_ui()
        self.load_existing_database()
        self.is_analyzing = False
        
    def setup_ui(self):
        main_frame = ttk.Frame(self.root, padding="8")
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        title_frame = tk.Frame(main_frame)
        title_frame.pack(pady=(0, 6))
        
        tk_label = tk.Label(title_frame, text="TK", font=('Arial', 16, 'bold'), fg='#E53935')
        tk_label.pack(side=tk.LEFT)
        
        rest_label = tk.Label(title_frame, text=" SAMPLE ANALYZER", font=('Arial', 16, 'bold'))
        rest_label.pack(side=tk.LEFT)
        
        self.db_status_var = tk.StringVar(value="Loading...")
        self.db_status_label = ttk.Label(main_frame, textvariable=self.db_status_var, font=('Arial', 8))
        self.db_status_label.pack(anchor=tk.W, pady=(0, 6))
        
        folder_frame = ttk.Frame(main_frame)
        folder_frame.pack(fill=tk.X, pady=(0, 6))
        
        self.folder_var = tk.StringVar()
        self.folder_entry = ttk.Entry(folder_frame, textvariable=self.folder_var)
        self.folder_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 4))
        
        browse_btn = ttk.Button(folder_frame, text="Browse...", command=self.browse_folder, width=10)
        browse_btn.pack(side=tk.RIGHT)
        
        options_frame = ttk.Frame(main_frame)
        options_frame.pack(fill=tk.X, pady=(0, 6))
        
        self.skip_existing_var = tk.BooleanVar(value=True)
        skip_check = ttk.Checkbutton(options_frame, text="Skip existing", variable=self.skip_existing_var)
        skip_check.pack(side=tk.LEFT, padx=(0, 10))
        
        self.rescan_var = tk.BooleanVar(value=False)
        rescan_check = ttk.Checkbutton(options_frame, text="Force re-analysis", variable=self.rescan_var, command=self.on_rescan_toggle)
        rescan_check.pack(side=tk.LEFT, padx=(0, 15))
        
        import multiprocessing
        cpu_count = multiprocessing.cpu_count()
        default_workers = min(4, cpu_count)
        
        workers_label = ttk.Label(options_frame, text="Workers:")
        workers_label.pack(side=tk.LEFT, padx=(0, 4))
        
        self.workers_var = tk.IntVar(value=default_workers)
        workers_spin = ttk.Spinbox(options_frame, from_=1, to=cpu_count, width=3, 
                                    textvariable=self.workers_var, state='readonly')
        workers_spin.pack(side=tk.LEFT)
        
        self.indexed_frame = ttk.LabelFrame(main_frame, text="Indexed Folders", padding="4")
        self.indexed_frame.pack(fill=tk.X, pady=(0, 6))
        self.indexed_canvas = tk.Canvas(self.indexed_frame, height=60)
        self.indexed_scrollbar = ttk.Scrollbar(self.indexed_frame, orient=tk.VERTICAL, command=self.indexed_canvas.yview)
        self.indexed_inner = ttk.Frame(self.indexed_canvas)
        
        self.indexed_canvas.configure(yscrollcommand=self.indexed_scrollbar.set)
        self.indexed_scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.indexed_canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.indexed_canvas_window = self.indexed_canvas.create_window((0, 0), window=self.indexed_inner, anchor=tk.NW)
        
        self.indexed_inner.bind("<Configure>", lambda e: self.indexed_canvas.configure(scrollregion=self.indexed_canvas.bbox("all")))
        self.indexed_canvas.bind("<Configure>", lambda e: self.indexed_canvas.itemconfig(self.indexed_canvas_window, width=e.width))
        
        self.exclude_frame = ttk.LabelFrame(main_frame, text="Exclude folders from re-analysis", padding="4")
        self.exclude_canvas = tk.Canvas(self.exclude_frame, height=80)
        self.exclude_scrollbar = ttk.Scrollbar(self.exclude_frame, orient=tk.VERTICAL, command=self.exclude_canvas.yview)
        self.exclude_inner = ttk.Frame(self.exclude_canvas)
        
        self.exclude_canvas.configure(yscrollcommand=self.exclude_scrollbar.set)
        self.exclude_scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.exclude_canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.exclude_canvas_window = self.exclude_canvas.create_window((0, 0), window=self.exclude_inner, anchor=tk.NW)
        
        self.exclude_inner.bind("<Configure>", lambda e: self.exclude_canvas.configure(scrollregion=self.exclude_canvas.bbox("all")))
        self.exclude_canvas.bind("<Configure>", lambda e: self.exclude_canvas.itemconfig(self.exclude_canvas_window, width=e.width))
        
        self.btn_frame = ttk.Frame(main_frame)
        self.btn_frame.pack(fill=tk.X, pady=(0, 6))
        
        self.analyze_btn = ttk.Button(self.btn_frame, text="▶ Add Folder", command=self.start_analysis)
        self.analyze_btn.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 4))
        
        self.clear_btn = ttk.Button(self.btn_frame, text="🗑 Clear Database", command=self.clear_database)
        self.clear_btn.pack(side=tk.RIGHT)
        
        progress_frame = ttk.Frame(main_frame)
        progress_frame.pack(fill=tk.X, pady=(0, 6))
        
        self.progress_var = tk.DoubleVar()
        self.progress_bar = ttk.Progressbar(progress_frame, variable=self.progress_var, maximum=100)
        self.progress_bar.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))
        
        self.status_var = tk.StringVar(value="Ready")
        self.status_label = ttk.Label(progress_frame, textvariable=self.status_var, width=30, anchor=tk.W)
        self.status_label.pack(side=tk.RIGHT)
        
        log_frame = ttk.LabelFrame(main_frame, text="Log", padding="4")
        log_frame.pack(fill=tk.BOTH, expand=True)
        
        self.log_text = tk.Text(log_frame, height=8, wrap=tk.WORD, font=('Consolas', 8))
        scrollbar = ttk.Scrollbar(log_frame, orient=tk.VERTICAL, command=self.log_text.yview)
        self.log_text.configure(yscrollcommand=scrollbar.set)
        
        self.log_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        
        self.log("TK Sample Analyzer ready")
        self.log(f"Database: {OUTPUT_FILE}")
        
    def load_existing_database(self):
        self.existing_database = None
        self.existing_paths = set()
        
        if OUTPUT_FILE.exists():
            try:
                with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
                    self.existing_database = json.load(f)
                    samples = self.existing_database.get("samples", [])
                    self.existing_paths = {s.get("path") for s in samples if s.get("path")}
                    
                    count = len(samples)
                    cats = self.existing_database.get("categories", {})
                    cat_str = ", ".join([f"{k}: {v}" for k, v in sorted(cats.items(), key=lambda x: -x[1])[:5]])
                    
                    self.db_status_var.set(f"✓ {count} samples in database | {cat_str}")
                    self.log(f"Database loaded: {count} samples")
                    
                    self.extract_root_folders()
            except Exception as e:
                self.db_status_var.set("⚠ Database corrupt or unreadable")
                self.log(f"Error loading database: {e}")
                self.populate_indexed_folders()
        else:
            self.db_status_var.set("○ No database found - start scanning!")
            self.log("No existing database found")
            self.populate_indexed_folders()
    
    def extract_root_folders(self):
        self.scanned_root_folders = set()
        if self.existing_database:
            scanned_folders = self.existing_database.get("scanned_folders", [])
            if scanned_folders:
                self.scanned_root_folders = set(scanned_folders)
            else:
                sample_parents = {}
                for sample in self.existing_database.get("samples", []):
                    path = sample.get("path", "")
                    if path:
                        p = Path(path)
                        parent = p.parent.parent
                        parent_str = str(parent)
                        if parent_str not in sample_parents:
                            sample_parents[parent_str] = 0
                        sample_parents[parent_str] += 1
                
                for parent_path, count in sample_parents.items():
                    if count >= 1:
                        self.scanned_root_folders.add(parent_path)
        
        self.populate_indexed_folders()
    
    def populate_indexed_folders(self):
        for widget in self.indexed_inner.winfo_children():
            widget.destroy()
        
        if not self.scanned_root_folders:
            lbl = ttk.Label(self.indexed_inner, text="No folders indexed yet", font=('Arial', 8, 'italic'), foreground='gray')
            lbl.pack(anchor=tk.W, pady=2)
            return
        
        for folder in sorted(self.scanned_root_folders):
            folder_normalized = os.path.normpath(folder).lower()
            folder_samples = sum(1 for s in self.existing_database.get("samples", []) 
                               if os.path.normpath(s.get("path", "")).lower().startswith(folder_normalized))
            
            folder_frame = ttk.Frame(self.indexed_inner)
            folder_frame.pack(anchor=tk.W, fill=tk.X, pady=1)
            
            lbl = ttk.Label(folder_frame, text=f"📁 {folder}", font=('Arial', 8))
            lbl.pack(side=tk.LEFT)
            
            count_lbl = ttk.Label(folder_frame, text=f"({folder_samples})", font=('Arial', 8), foreground='gray')
            count_lbl.pack(side=tk.LEFT, padx=(4, 0))
            
    def on_rescan_toggle(self):
        if self.rescan_var.get():
            self.skip_existing_var.set(False)
            self.populate_exclude_folders()
            self.exclude_frame.pack(fill=tk.X, pady=(0, 6), before=self.btn_frame)
        else:
            self.exclude_frame.pack_forget()
            self.excluded_folders.clear()
    
    def populate_exclude_folders(self):
        for widget in self.exclude_inner.winfo_children():
            widget.destroy()
        self.folder_checkbuttons.clear()
        self.excluded_folders.clear()
        
        if not self.scanned_root_folders:
            lbl = ttk.Label(self.exclude_inner, text="No previously scanned folders found", font=('Arial', 8, 'italic'))
            lbl.pack(anchor=tk.W, pady=2)
            return
        
        for folder in sorted(self.scanned_root_folders):
            var = tk.BooleanVar(value=False)
            cb = ttk.Checkbutton(
                self.exclude_inner, 
                text=folder, 
                variable=var,
                command=lambda f=folder, v=var: self.toggle_exclude_folder(f, v)
            )
            cb.pack(anchor=tk.W, pady=1)
            self.folder_checkbuttons[folder] = var
    
    def toggle_exclude_folder(self, folder, var):
        if var.get():
            self.excluded_folders.add(folder)
        else:
            self.excluded_folders.discard(folder)
        
    def browse_folder(self):
        folder = filedialog.askdirectory(title="Select Sample Folder")
        if folder:
            self.folder_var.set(folder)
            self.log(f"Folder selected: {folder}")
            self.check_new_files(folder)
            
    def check_new_files(self, folder):
        SUPPORTED_EXTENSIONS = {'.wav', '.mp3', '.aif', '.aiff', '.flac', '.ogg', '.m4a'}
        sample_folder = Path(folder)
        
        audio_files = []
        for ext in SUPPORTED_EXTENSIONS:
            audio_files.extend(sample_folder.rglob(f"*{ext}"))
            audio_files.extend(sample_folder.rglob(f"*{ext.upper()}"))
        audio_files = list(set(audio_files))
        
        total = len(audio_files)
        new_count = sum(1 for f in audio_files if str(f) not in self.existing_paths)
        existing_count = total - new_count
        
        self.log(f"  Total: {total} files")
        self.log(f"  New: {new_count} | Already in database: {existing_count}")
        
    def clear_database(self):
        if messagebox.askyesno("Clear Database", "Are you sure you want to clear the entire database?\n\nAll sample analyses will be deleted."):
            try:
                if OUTPUT_FILE.exists():
                    OUTPUT_FILE.unlink()
                self.existing_database = None
                self.existing_paths = set()
                self.db_status_var.set("○ Database cleared - start scanning!")
                self.log("Database cleared")
            except Exception as e:
                self.log(f"Error clearing: {e}")
            
    def log(self, message):
        self.log_text.insert(tk.END, f"{message}\n")
        self.log_text.see(tk.END)
        self.root.update_idletasks()
        
    def update_progress(self, current, total, filename=""):
        if total > 0:
            percent = (current / total) * 100
            self.progress_var.set(percent)
            self.status_var.set(f"[{current}/{total}] {filename[:40]}...")
        self.root.update_idletasks()
        
    def start_analysis(self):
        folder = self.folder_var.get()
        
        if not folder:
            messagebox.showwarning("No folder", "Please select a sample folder first!")
            return
            
        if not os.path.isdir(folder):
            messagebox.showerror("Error", f"Folder does not exist:\n{folder}")
            return
            
        self.is_analyzing = True
        self.analyze_btn.configure(state='disabled', text="⏳ Analyzing...")
        self.clear_btn.configure(state='disabled')
        self.progress_var.set(0)
        
        skip_existing = self.skip_existing_var.get() and not self.rescan_var.get()
        excluded = set(self.excluded_folders) if self.rescan_var.get() else set()
        
        thread = threading.Thread(target=self.run_analysis, args=(folder, skip_existing, excluded), daemon=True)
        thread.start()
        
    def run_analysis(self, folder, skip_existing, excluded_folders=None):
        try:
            self.log("\n" + "="*50)
            self.log("Analysis started...")
            if skip_existing:
                self.log("Mode: Scan new samples only")
            else:
                self.log("Mode: (Re)scan all samples")
            self.log("="*50)
            
            try:
                import librosa
                import numpy as np
            except ImportError as e:
                self.root.after(0, lambda: messagebox.showerror(
                    "Missing packages",
                    "librosa and/or numpy not installed!\n\n"
                    "Open Command Prompt and type:\n"
                    "python -m pip install librosa numpy"
                ))
                self.finish_analysis(False)
                return
            
            SUPPORTED_EXTENSIONS = {'.wav', '.mp3', '.aif', '.aiff', '.flac', '.ogg', '.m4a'}
            
            DRUM_KEYWORDS = {
                'kick': ['kick', 'bass drum', 'bassdrum', 'bd_', '_bd', ' bd '],
                'snare': ['snare', 'snr_', '_snr', ' snr ', 'clap', 'rimshot', 'rim shot'],
                'hihat': ['hihat', 'hi-hat', 'hi hat', 'hh_', '_hh', ' hh ', 'closed hat', 'open hat', 'pedal hat',
                          'closedhat', 'openhat', 'closehat', 'hat_', '_hat', 'hats', 'closed_', 'open_'],
                'tom': ['tom_', '_tom', ' tom ', 'floor tom', 'rack tom'],
                'cymbal': ['cymbal', 'crash', 'ride', 'splash'],
                'percussion': ['perc', 'shaker', 'tambourine', 'conga', 'bongo', 'cowbell'],
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
                'bass': ['bass', 'sub_', '_sub', ' sub ', '808 bass', 'synth bass', 'reese', '808_'],
                'synth': ['synth', 'lead_', '_lead', ' lead ', 'pluck', 'arp_', '_arp', ' arp ', 'stab'],
                'pad': ['pad_', '_pad', ' pad ', 'ambient', 'atmosphere', 'drone', 'texture'],
                'keys': ['piano', 'pno', 'keys', 'organ', 'rhodes', 'wurli', 'epiano', 'e_piano'],
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
                'loop': ['loop', 'groove', 'pattern', 'phrase', 'riff']
            }
            
            ALL_CATEGORIES = list(DRUM_KEYWORDS.keys()) + list(OTHER_KEYWORDS.keys()) + ['other']
            
            ONESHOT_KEYWORDS = ['oneshot', 'one-shot', 'one shot', 'single hit', 'single_']
            LOOP_KEYWORDS = ['loop', 'beat', 'groove', 'pattern', 'breakbeat', 'drumloop', 
                            'toploop', 'phrase', 'riff', 'sequence', 'rhythm', 'backing',
                            'arp loop', 'synth loop', 'bass loop', 'melody', 'hook', 'motif']
            
            import re
            
            def keyword_match(keyword, text):
                if len(keyword) <= 3:
                    pattern = r'(?:^|[\s_\-\.])' + re.escape(keyword) + r'(?:$|[\s_\-\.])'
                    return bool(re.search(pattern, text))
                else:
                    return keyword in text
            
            def extract_features(y, sr):
                features = {}
                
                features['duration'] = librosa.get_duration(y=y, sr=sr)
                features['spectral_centroid'] = float(np.mean(librosa.feature.spectral_centroid(y=y, sr=sr)))
                features['spectral_rolloff'] = float(np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr, roll_percent=0.85)))
                features['spectral_bandwidth'] = float(np.mean(librosa.feature.spectral_bandwidth(y=y, sr=sr)))
                features['zero_crossing_rate'] = float(np.mean(librosa.feature.zero_crossing_rate(y=y)))
                features['spectral_flatness'] = float(np.mean(librosa.feature.spectral_flatness(y=y)))
                
                spectral_contrast = librosa.feature.spectral_contrast(y=y, sr=sr)
                features['spectral_contrast'] = np.mean(spectral_contrast, axis=1).tolist()
                
                peak_amplitude = np.max(np.abs(y))
                rms_amplitude = np.sqrt(np.mean(y**2))
                features['peak_amplitude'] = float(peak_amplitude)
                features['crest_factor'] = float(peak_amplitude / rms_amplitude) if rms_amplitude > 0 else 0
                features['crest_factor_db'] = float(20 * np.log10(features['crest_factor'])) if features['crest_factor'] > 0 else 0
                
                features['brightness'] = features['spectral_centroid'] / (sr / 2)
                
                try:
                    harmonic, percussive = librosa.effects.hpss(y)
                    harmonic_energy = np.sum(harmonic**2)
                    total_energy = np.sum(y**2)
                    features['harmonicity'] = float(harmonic_energy / total_energy) if total_energy > 0 else 0.5
                except:
                    features['harmonicity'] = 0.5
                
                features['noisiness'] = features['spectral_flatness']
                
                rms = librosa.feature.rms(y=y)[0]
                features['rms_mean'] = float(np.mean(rms))
                features['rms_std'] = float(np.std(rms))
                
                if len(rms) > 1:
                    rms_normalized = rms / np.max(rms) if np.max(rms) > 0 else rms
                    features['amplitude_envelope'] = rms_normalized[:20].tolist()
                else:
                    features['amplitude_envelope'] = [1.0]
                
                if len(rms) > 10:
                    attack_frames = min(10, len(rms) // 4)
                    features['attack_slope'] = float(np.max(rms[:attack_frames]) / (attack_frames + 0.001))
                    peak_idx = np.argmax(rms)
                    features['attack_time'] = float(peak_idx * 512 / sr)
                    if peak_idx < len(rms) - 1:
                        decay_rms = rms[peak_idx:]
                        if len(decay_rms) > 1:
                            features['decay_rate'] = float((decay_rms[0] - decay_rms[-1]) / (len(decay_rms) + 0.001))
                            threshold = decay_rms[0] * 0.1
                            decay_indices = np.where(decay_rms < threshold)[0]
                            if len(decay_indices) > 0:
                                features['decay_time'] = float(decay_indices[0] * 512 / sr)
                            else:
                                features['decay_time'] = float(len(decay_rms) * 512 / sr)
                        else:
                            features['decay_rate'] = 0.0
                            features['decay_time'] = 0.0
                    else:
                        features['decay_rate'] = 0.0
                        features['decay_time'] = 0.0
                else:
                    features['attack_slope'] = 0.0
                    features['attack_time'] = 0.0
                    features['decay_rate'] = 0.0
                    features['decay_time'] = 0.0
                
                try:
                    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13)
                    features['mfcc_mean'] = [float(np.mean(mfcc[i])) for i in range(13)]
                    features['mfcc_std'] = [float(np.std(mfcc[i])) for i in range(13)]
                except:
                    features['mfcc_mean'] = [0.0] * 13
                    features['mfcc_std'] = [0.0] * 13
                
                try:
                    chroma = librosa.feature.chroma_stft(y=y, sr=sr)
                    features['chroma_mean'] = np.mean(chroma, axis=1).tolist()
                except:
                    features['chroma_mean'] = [0.0] * 12
                
                onset_env = librosa.onset.onset_strength(y=y, sr=sr)
                features['onset_env'] = onset_env
                onsets = librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr)
                features['onset_count'] = len(onsets)
                
                try:
                    tempo, _ = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr)
                    if isinstance(tempo, np.ndarray):
                        tempo = tempo[0] if len(tempo) > 0 else 0
                    features['tempo'] = float(tempo) if tempo > 0 else None
                except:
                    features['tempo'] = None
                
                try:
                    pitches, magnitudes = librosa.piptrack(y=y, sr=sr, fmin=30, fmax=2000)
                    pitch_values = []
                    for t in range(pitches.shape[1]):
                        index = magnitudes[:, t].argmax()
                        pitch = pitches[index, t]
                        if pitch > 0:
                            pitch_values.append(pitch)
                    features['pitch_hz'] = float(np.median(pitch_values)) if pitch_values else None
                    features['pitch_confidence'] = len(pitch_values) / pitches.shape[1] if pitches.shape[1] > 0 else 0
                except:
                    features['pitch_hz'] = None
                    features['pitch_confidence'] = 0
                
                feature_vector = np.concatenate([
                    [features['brightness'], features['harmonicity'], features['noisiness'], features['crest_factor']],
                    [features['spectral_centroid'] / 10000, features['spectral_rolloff'] / 20000, features['spectral_bandwidth'] / 5000],
                    [features['attack_time'] * 10, features['decay_time']],
                    np.array(features['mfcc_mean']) / 100,
                    np.array(features['chroma_mean'])
                ])
                features['feature_vector'] = (feature_vector / (np.linalg.norm(feature_vector) + 1e-8)).tolist()
                
                return features
            
            def get_keyword_scores(filepath):
                scores = {cat: 0.0 for cat in ALL_CATEGORIES}
                path_lower = str(filepath).lower()
                filename_lower = filepath.name.lower()
                folder_lower = str(filepath.parent).lower()
                
                for category, keywords in DRUM_KEYWORDS.items():
                    for kw in keywords:
                        if keyword_match(kw, filename_lower):
                            scores[category] += 1.0
                        elif keyword_match(kw, path_lower):
                            scores[category] += 0.5
                
                for category, keywords in OTHER_KEYWORDS.items():
                    for kw in keywords:
                        if keyword_match(kw, filename_lower):
                            scores[category] += 1.0
                        elif keyword_match(kw, path_lower):
                            scores[category] += 0.5
                
                for kw in DRUMLOOP_FOLDER_KEYWORDS:
                    if kw in folder_lower:
                        scores['drumloop'] += 1.5
                        break
                
                if scores['drumloop'] < 0.5:
                    if ('drum' in folder_lower or 'drums' in folder_lower) and ('loop' in folder_lower or 'lps' in folder_lower):
                        scores['drumloop'] += 1.2
                    elif 'full_drums' in path_lower or 'full drums' in path_lower:
                        scores['drumloop'] += 1.5
                
                return scores
            
            def get_audio_scores(features):
                scores = {cat: 0.0 for cat in ALL_CATEGORIES}
                
                dur = features['duration']
                sc = features['spectral_centroid']
                rolloff = features['spectral_rolloff']
                bandwidth = features['spectral_bandwidth']
                zcr = features['zero_crossing_rate']
                rms = features['rms_mean']
                attack = features['attack_slope']
                decay = features['decay_rate']
                onset_count = features['onset_count']
                mfcc = features['mfcc_mean']
                
                brightness = features.get('brightness', sc / 11025)
                harmonicity = features.get('harmonicity', 0.5)
                noisiness = features.get('noisiness', 0.5)
                crest_factor = features.get('crest_factor', 3.0)
                attack_time = features.get('attack_time', 0.01)
                
                is_tonal = harmonicity > 0.6 or features['pitch_confidence'] > 0.5
                is_noisy = noisiness > 0.3 or harmonicity < 0.3
                is_percussive = crest_factor > 6 and attack_time < 0.02
                is_very_short = dur < 0.3
                is_short = dur < 0.8
                is_medium = 0.8 <= dur < 2.0
                is_long = dur >= 2.0
                
                if sc < 600 and is_short and not is_tonal and is_percussive:
                    scores['kick'] += 1.2
                if sc < 300 and attack > 0.01:
                    scores['kick'] += 0.5
                if rms > 0.15 and sc < 800 and harmonicity < 0.4:
                    scores['kick'] += 0.4
                if crest_factor > 8 and sc < 500:
                    scores['kick'] += 0.3
                
                if 1200 < sc < 4000 and is_short and is_noisy and is_percussive:
                    scores['snare'] += 1.2
                if attack > 0.01 and 1000 < sc < 4500 and noisiness > 0.2:
                    scores['snare'] += 0.4
                if bandwidth > 2000 and is_very_short and crest_factor > 5:
                    scores['snare'] += 0.3
                
                if sc > 3500 and is_short and is_noisy:
                    scores['hihat'] += 1.0
                if sc > 5000 and noisiness > 0.4:
                    scores['hihat'] += 0.6
                if zcr > 0.15 and brightness > 0.5:
                    scores['hihat'] += 0.3
                if not is_tonal and sc > 4000 and is_very_short:
                    scores['hihat'] += 0.5
                
                if sc > 5000 and is_medium and noisiness > 0.3:
                    scores['cymbal'] += 1.0
                if decay < 0.001 and sc > 4000 and dur > 0.5:
                    scores['cymbal'] += 0.4
                if brightness > 0.6 and harmonicity < 0.4 and is_medium:
                    scores['cymbal'] += 0.3
                
                if not is_tonal and is_short and 600 < sc < 3000 and is_percussive:
                    scores['percussion'] += 0.6
                if 2 <= onset_count <= 5 and is_short and crest_factor > 4:
                    scores['percussion'] += 0.3
                
                if sc > 800 and sc < 2500 and is_short and not is_tonal:
                    scores['tom'] += 0.5
                if attack > 0.005 and sc < 2000 and harmonicity < 0.5:
                    scores['tom'] += 0.3
                
                if sc < 500 and is_tonal and harmonicity > 0.5:
                    scores['bass'] += 1.2
                if sc < 300 and brightness < 0.1:
                    scores['bass'] += 0.4
                if features['pitch_confidence'] > 0.7 and sc < 600:
                    scores['bass'] += 0.3
                
                if is_tonal and is_medium and harmonicity > 0.5:
                    scores['synth'] += 0.6
                if is_tonal and 1000 < sc < 4000 and noisiness < 0.2:
                    scores['synth'] += 0.3
                if is_tonal and not is_long and attack > 0.005:
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
                if is_tonal and bandwidth > 2000 and bandwidth < 6000 and dur > 0.5 and harmonicity > 0.4:
                    scores['guitar'] += 0.4
                if mfcc[2] > 10 and is_tonal and dur > 0.3:
                    scores['guitar'] += 0.2
                
                if dur > 1.5 and onset_count >= 4:
                    scores['loop'] += 0.6
                if dur > 2.5 and onset_count >= 6:
                    scores['loop'] += 0.4
                
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
            
            def ensemble_classify(filepath, features):
                keyword_scores = get_keyword_scores(filepath)
                audio_scores = get_audio_scores(features)
                
                KEYWORD_WEIGHT = 3.0
                AUDIO_WEIGHT = 1.0
                
                combined_scores = {}
                for cat in ALL_CATEGORIES:
                    combined_scores[cat] = (keyword_scores[cat] * KEYWORD_WEIGHT) + (audio_scores[cat] * AUDIO_WEIGHT)
                
                specific_categories = ['guitar', 'vocal', 'fx', 'keys', 'strings', 'bass']
                ambiguous_categories = ['pad', 'synth', 'loop']
                
                for specific_cat in specific_categories:
                    if keyword_scores.get(specific_cat, 0) >= 1.0:
                        for ambig_cat in ambiguous_categories:
                            if combined_scores.get(ambig_cat, 0) > 0:
                                combined_scores[ambig_cat] *= 0.3
                
                sorted_cats = sorted(combined_scores.items(), key=lambda x: -x[1])
                best_cat = sorted_cats[0][0]
                best_score = sorted_cats[0][1]
                
                secondary_categories = []
                if len(sorted_cats) > 1:
                    threshold = best_score * 0.6
                    for cat, score in sorted_cats[1:4]:
                        if score >= threshold and score >= 0.5:
                            secondary_categories.append(cat)
                
                if best_score < 0.3:
                    best_cat = 'other'
                
                is_drum = best_cat in DRUM_KEYWORDS
                
                confidence = min(best_score / 3.0, 1.0)
                
                return best_cat, is_drum, confidence, secondary_categories
            
            def detect_loop_from_name(filepath):
                path_lower = str(filepath).lower()
                filename_lower = filepath.name.lower()
                
                for kw in LOOP_KEYWORDS:
                    if kw in filename_lower or kw in path_lower:
                        return True
                
                for kw in ONESHOT_KEYWORDS:
                    if kw in filename_lower or kw in path_lower:
                        return False
                
                return None
            
            def detect_loop_from_audio(features):
                dur = features['duration']
                onset_count = features['onset_count']
                tempo = features['tempo']
                onset_env = features['onset_env']
                
                if dur < 0.5:
                    return False, 0.9
                
                if dur > 3.0 and onset_count >= 4:
                    return True, 0.8
                
                if dur > 1.5 and onset_count >= 4 and tempo and 50 <= tempo <= 200:
                    try:
                        intervals = np.diff(librosa.onset.onset_detect(onset_envelope=onset_env, sr=22050, units='time'))
                        if len(intervals) >= 2:
                            interval_std = np.std(intervals)
                            interval_mean = np.mean(intervals)
                            if interval_mean > 0.05 and interval_std / interval_mean < 0.5:
                                return True, 0.7
                    except:
                        pass
                
                if dur > 2.0 and onset_count >= 6:
                    return True, 0.6
                
                return False, 0.5
            
            def hz_to_note(hz):
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
            
            sample_folder = Path(folder)
            audio_files = []
            
            self.log("Searching for audio files...")
            for ext in SUPPORTED_EXTENSIONS:
                audio_files.extend(sample_folder.rglob(f"*{ext}"))
                audio_files.extend(sample_folder.rglob(f"*{ext.upper()}"))
            
            audio_files = list(set(audio_files))
            
            if excluded_folders:
                excluded_count_before = len(audio_files)
                def is_excluded(filepath):
                    path_str = str(filepath)
                    for excl in excluded_folders:
                        if path_str.startswith(excl) or excl in path_str:
                            return True
                    return False
                audio_files = [f for f in audio_files if not is_excluded(f)]
                excluded_by_folder = excluded_count_before - len(audio_files)
                if excluded_by_folder > 0:
                    self.log(f"Excluded by folder filter: {excluded_by_folder} files")
            
            if skip_existing:
                files_to_scan = [f for f in audio_files if str(f) not in self.existing_paths]
                skipped_count = len(audio_files) - len(files_to_scan)
                self.log(f"Found: {len(audio_files)} files")
                self.log(f"Skipped (already in database): {skipped_count}")
                self.log(f"To scan: {len(files_to_scan)} new files")
            else:
                files_to_scan = audio_files
                skipped_count = 0
                self.log(f"To scan: {len(files_to_scan)} files")
            
            total = len(files_to_scan)
            
            if total == 0:
                self.log("No new files to scan!")
                self.root.after(0, lambda: messagebox.showinfo(
                    "No new files",
                    "All samples in this folder have already been analyzed.\n\n"
                    "Check 'Force re-analysis' to scan again."
                ))
                self.finish_analysis(True)
                return
            
            new_results = []
            errors = []
            processed_count = [0]
            
            num_workers = self.workers_var.get()
            self.log(f"Using {num_workers} worker(s) for analysis...")
            
            def analyze_single_file(filepath):
                try:
                    y, sr = librosa.load(filepath, sr=22050, mono=True, duration=30)
                    
                    features = extract_features(y, sr)
                    
                    category, is_drum, confidence, secondary_categories = ensemble_classify(filepath, features)
                    
                    name_loop = detect_loop_from_name(filepath)
                    audio_loop, loop_conf = detect_loop_from_audio(features)
                    
                    if name_loop == False:
                        is_loop = False
                    elif name_loop == True:
                        is_loop = True
                    elif audio_loop:
                        is_loop = True
                    else:
                        is_loop = False
                    
                    sc = features['spectral_centroid']
                    rms = features['rms_mean']
                    
                    tags = [category]
                    
                    for sec_cat in secondary_categories:
                        if sec_cat not in tags:
                            tags.append(sec_cat)
                    
                    if is_loop:
                        tags.append("loop")
                    else:
                        tags.append("one-shot")
                    
                    if sc > 5000:
                        tags.append("bright")
                    elif sc < 1000:
                        tags.append("dark")
                    
                    if rms > 0.1:
                        tags.append("loud")
                    elif rms < 0.02:
                        tags.append("soft")
                    
                    if features['attack_slope'] > 0.02:
                        tags.append("punchy")
                    
                    if features.get('attack_time', 0.02) < 0.005:
                        tags.append("snappy")
                    
                    if features.get('decay_time', 0.1) > 0.5:
                        tags.append("sustained")
                    
                    if features.get('harmonicity', 0.5) > 0.7:
                        tags.append("tonal")
                    
                    if 1000 < sc < 3000:
                        tags.append("warm")
                    
                    cf = features.get('crest_factor', 3.0)
                    if cf < 2.0:
                        tags.append("compressed")
                    elif cf > 5.0:
                        tags.append("dynamic")
                    
                    def extract_bpm_from_name(fp):
                        import re
                        filename = fp.stem
                        folder = fp.parent.name
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
                    
                    def extract_key_from_name(fp):
                        import re
                        filename = fp.stem
                        folder = fp.parent.name
                        
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
                    
                    def key_to_hz(key_str):
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
                        return 440.0 * (2 ** ((midi_note - 69) / 12.0))
                    
                    bpm_from_name = extract_bpm_from_name(filepath)
                    final_bpm = None
                    if bpm_from_name:
                        final_bpm = bpm_from_name
                    elif is_loop and features['tempo'] and features['onset_count'] >= 4:
                        audio_bpm = features['tempo']
                        if 50 <= audio_bpm <= 200:
                            final_bpm = round(audio_bpm)
                    
                    key_from_name = extract_key_from_name(filepath)
                    final_pitch_note = None
                    final_pitch_hz = None
                    
                    if key_from_name:
                        final_pitch_note = key_from_name
                        final_pitch_hz = key_to_hz(key_from_name)
                    elif features['pitch_hz'] and features['pitch_hz'] > 0:
                        final_pitch_hz = features['pitch_hz']
                        final_pitch_note = hz_to_note(features['pitch_hz'])
                    
                    try:
                        rel_folder = str(filepath.parent.relative_to(sample_folder))
                    except:
                        rel_folder = str(filepath.parent)
                    
                    return {
                        "path": str(filepath),
                        "name": filepath.name,
                        "folder": rel_folder if rel_folder != "." else "",
                        "category": category,
                        "secondary_categories": secondary_categories if secondary_categories else None,
                        "is_drum": is_drum,
                        "confidence": round(confidence, 2),
                        "duration": round(features['duration'], 3),
                        "is_loop": is_loop,
                        "bpm": final_bpm,
                        "pitch_hz": round(final_pitch_hz, 1) if final_pitch_hz else None,
                        "pitch_note": final_pitch_note,
                        "brightness": round(features.get('brightness', sc / 11025), 3),
                        "harmonicity": round(features.get('harmonicity', 0.5), 3),
                        "noisiness": round(features.get('noisiness', 0.5), 3),
                        "crest_factor": round(features.get('crest_factor', 3.0), 2),
                        "crest_factor_db": round(features.get('crest_factor_db', 9.5), 1),
                        "attack_time": round(features.get('attack_time', 0.01), 4),
                        "decay_time": round(features.get('decay_time', 0.1), 4),
                        "energy": round(rms * 100, 2),
                        "peak_db": round(20 * np.log10(features.get('peak_amplitude', 0.5) + 1e-8), 1),
                        "rms_db": round(20 * np.log10(rms + 1e-8), 1),
                        "spectral_centroid": round(sc, 1),
                        "spectral_rolloff": round(features['spectral_rolloff'], 1),
                        "spectral_bandwidth": round(features['spectral_bandwidth'], 1),
                        "onset_count": features['onset_count'],
                        "tags": tags,
                        "feature_vector": features.get('feature_vector', []),
                        "chroma": features.get('chroma_mean', []),
                        "mfcc": [round(m, 3) for m in features['mfcc_mean']]
                    }
                    
                except Exception as e:
                    return {"error": str(e), "path": str(filepath)}
            
            with ThreadPoolExecutor(max_workers=num_workers) as executor:
                future_to_file = {executor.submit(analyze_single_file, f): f for f in files_to_scan}
                
                for future in as_completed(future_to_file):
                    filepath = future_to_file[future]
                    processed_count[0] += 1
                    
                    self.root.after(0, lambda c=processed_count[0], t=total, f=filepath.name: 
                                    self.update_progress(c, t, f))
                    
                    try:
                        result = future.result()
                        if "error" in result:
                            errors.append({"path": result["path"], "error": result["error"]})
                        else:
                            new_results.append(result)
                    except Exception as e:
                        errors.append({"path": str(filepath), "error": str(e)})
            
            if skip_existing and self.existing_database:
                existing_samples = self.existing_database.get("samples", [])
                
                if self.rescan_var.get():
                    scanned_paths = {r["path"] for r in new_results}
                    existing_samples = [s for s in existing_samples if s["path"] not in scanned_paths]
                
                all_samples = existing_samples + new_results
            else:
                all_samples = new_results
            
            category_counts = {}
            for s in all_samples:
                cat = s.get("category", "other")
                category_counts[cat] = category_counts.get(cat, 0) + 1
            
            drum_count = sum(1 for r in all_samples if r.get("is_drum"))
            
            existing_scanned_folders = []
            if self.existing_database:
                existing_scanned_folders = self.existing_database.get("scanned_folders", [])
            if folder not in existing_scanned_folders:
                existing_scanned_folders.append(folder)
            
            data = {
                "version": "3.0",
                "analyzer": "TK Sample Analyzer GUI (Ensemble)",
                "sample_count": len(all_samples),
                "drum_count": drum_count,
                "other_count": len(all_samples) - drum_count,
                "categories": category_counts,
                "scanned_folders": existing_scanned_folders,
                "samples": all_samples,
                "errors": errors if errors else None
            }
            
            data = sanitize_for_json(data)
            
            with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            
            self.log("\n" + "="*50)
            self.log("ANALYSIS COMPLETED!")
            self.log("="*50)
            self.log(f"Newly analyzed: {len(new_results)} files")
            self.log(f"Errors: {len(errors)} files")
            self.log(f"Total in database: {len(all_samples)} samples")
            self.log(f"\nCategories:")
            for cat, count in sorted(category_counts.items(), key=lambda x: -x[1]):
                self.log(f"  {cat:15} : {count}")
            self.log(f"\nSaved to:\n{OUTPUT_FILE}")
            
            self.root.after(0, self.load_existing_database)
            
            self.finish_analysis(True)
            
            self.root.after(0, lambda: messagebox.showinfo(
                "Done!",
                f"Analysis completed!\n\n"
                f"Newly added: {len(new_results)} samples\n"
                f"Total in database: {len(all_samples)} samples\n\n"
                f"Open TK Media Browser and click on the 'AI' tab."
            ))
            
        except Exception as e:
            self.log(f"\nERROR: {str(e)}")
            import traceback
            self.log(traceback.format_exc())
            self.root.after(0, lambda: messagebox.showerror("Error", str(e)))
            self.finish_analysis(False)
            
    def finish_analysis(self, success):
        self.is_analyzing = False
        self.root.after(0, lambda: self.analyze_btn.configure(
            state='normal', 
            text="▶ Add Folder"
        ))
        self.root.after(0, lambda: self.clear_btn.configure(state='normal'))
        if success:
            self.root.after(0, lambda: self.progress_var.set(100))
            self.root.after(0, lambda: self.status_var.set("Done!"))
        else:
            self.root.after(0, lambda: self.status_var.set("Stopped"))


def main():
    check_single_instance()
    
    root = tk.Tk()
    
    style = ttk.Style()
    try:
        style.theme_use('vista')
    except:
        try:
            style.theme_use('clam')
        except:
            pass
    
    app = SampleAnalyzerGUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()
