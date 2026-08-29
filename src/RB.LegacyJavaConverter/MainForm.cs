using System.Diagnostics;
using System.Text;

namespace RB.LegacyJavaConverter;

public sealed class MainForm : Form
{
    private readonly RadioButton _radProject = new() { Text = "Mode A: Project folder (Forge source with src/)", AutoSize = true, Checked = true };
    private readonly RadioButton _radJar = new() { Text = "Mode B: Finished .jar file (decompile, not decrypt)", AutoSize = true };
    private readonly Label _lblInput = new() { Text = "Input project", AutoSize = true, ForeColor = Color.Gainsboro, Anchor = AnchorStyles.Left, Margin = new Padding(0, 10, 8, 4) };
    private readonly TextBox _txtInput = NewTextBox();
    private readonly TextBox _txtOutput = NewTextBox();
    private readonly TextBox _txtSource = NewTextBox();
    private readonly TextBox _txtMc = NewTextBox();
    private readonly TextBox _txtNeo = NewTextBox();
    private readonly TextBox _txtGecko = NewTextBox();
    private readonly CheckBox _chkCompile = NewCheck("Compile after convert (optional diagnostic; failures OK)", false);
    private readonly CheckBox _chkDry = NewCheck("Dry run (preview only — no files written)", false);
    private readonly CheckBox _chkContinueNeo = NewCheck("After decompile, also scaffold NeoForge 26.2", true);
    private readonly Label _lblOptionsHint = new()
    {
        AutoSize = true,
        ForeColor = Color.FromArgb(160, 170, 180),
        Margin = new Padding(12, 6, 8, 4),
        Text = "Uncheck Dry run to write the converted project."
    };
    private readonly Button _btnBrowseIn = NewButton("Browse...", 110);
    private readonly Button _btnBrowseOut = NewButton("Browse...", 110);
    private readonly Button _btnRun = NewButton("Convert", 130);
    private readonly Button _btnOpenOut = NewButton("Open output", 130);
    private readonly Button _btnClear = NewButton("Clear log", 120);
    private readonly ProgressBar _progress = new()
    {
        Style = ProgressBarStyle.Continuous,
        Height = 22,
        Margin = new Padding(8, 8, 0, 4),
        Dock = DockStyle.Fill
    };
    private readonly RichTextBox _log = new();
    private Process? _running;
    private System.Windows.Forms.Timer? _pollTimer;
    private string _lastOutput = "";
    private bool _busy;

    public MainForm()
    {
        Text = "RB Legacy Java Converter v1.5.0 — Project / JAR → NeoForge 26.2";
        ClientSize = new Size(980, 760);
        MinimumSize = new Size(840, 640);
        StartPosition = FormStartPosition.CenterScreen;
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { /* optional */ }
        BackColor = Color.FromArgb(32, 34, 40);
        ForeColor = Color.Gainsboro;
        Font = new Font("Segoe UI", 9.5f);
        AutoScaleMode = AutoScaleMode.Dpi;
        AutoScaleDimensions = new SizeF(96f, 96f);
        Padding = new Padding(12);

        var header = new TableLayoutPanel
        {
            ColumnCount = 1,
            RowCount = 2,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 0, 0, 8)
        };
        header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        header.Controls.Add(new Label
        {
            Text = "RB Legacy Java Converter v1.5.0 — Project or finished JAR → NeoForge 26.2",
            Font = new Font("Segoe UI Semibold", 12f),
            ForeColor = Color.White,
            AutoSize = true,
            Margin = new Padding(0, 0, 0, 2)
        }, 0, 0);
        header.Controls.Add(new Label
        {
            Text = "Experimental. Always writes to a new output folder. Original project/jar is never modified.",
            ForeColor = Color.FromArgb(140, 200, 140),
            AutoSize = true,
            Margin = new Padding(0, 0, 0, 8)
        }, 0, 1);

        var modePanel = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 0, 0, 8)
        };
        _radProject.ForeColor = Color.Gainsboro;
        _radJar.ForeColor = Color.Gainsboro;
        _radProject.Margin = new Padding(0, 2, 0, 2);
        _radJar.Margin = new Padding(0, 2, 0, 2);
        modePanel.Controls.Add(new Label
        {
            Text = "Choose input type first — Mode B switches Browse to a .jar file picker.",
            AutoSize = true,
            ForeColor = Color.Khaki,
            Margin = new Padding(0, 0, 0, 6)
        });
        modePanel.Controls.Add(_radProject);
        modePanel.Controls.Add(_radJar);

        var paths = new TableLayoutPanel
        {
            ColumnCount = 3,
            RowCount = 2,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 0, 0, 10)
        };
        paths.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120f));
        paths.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        paths.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120f));
        paths.RowStyles.Add(new RowStyle(SizeType.Absolute, 36f));
        paths.RowStyles.Add(new RowStyle(SizeType.Absolute, 36f));

        paths.Controls.Add(_lblInput, 0, 0);
        _txtInput.Dock = DockStyle.Fill;
        _txtInput.Margin = new Padding(0, 4, 8, 4);
        paths.Controls.Add(_txtInput, 1, 0);
        _btnBrowseIn.Dock = DockStyle.Fill;
        _btnBrowseIn.Margin = new Padding(0, 2, 0, 2);
        paths.Controls.Add(_btnBrowseIn, 2, 0);

        paths.Controls.Add(FieldLabel("Output folder"), 0, 1);
        _txtOutput.Dock = DockStyle.Fill;
        _txtOutput.Margin = new Padding(0, 4, 8, 4);
        paths.Controls.Add(_txtOutput, 1, 1);
        _btnBrowseOut.Dock = DockStyle.Fill;
        _btnBrowseOut.Margin = new Padding(0, 2, 0, 2);
        paths.Controls.Add(_btnBrowseOut, 2, 1);

        var versions = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = true,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 0, 0, 8)
        };
        versions.Controls.Add(LabeledField("Source", _txtSource, 110, "Auto-detect"));
        versions.Controls.Add(LabeledField("Target Minecraft", _txtMc, 90, "26.2"));
        versions.Controls.Add(LabeledField("NeoForge", _txtNeo, 170, "26.2.0.32-beta"));
        versions.Controls.Add(LabeledField("GeckoLib", _txtGecko, 90, "5.5.3"));

        var options = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 0, 0, 8)
        };
        var optRow1 = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = true,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Margin = new Padding(0)
        };
        _chkDry.Margin = new Padding(0, 4, 16, 4);
        _chkDry.ForeColor = Color.Khaki;
        _chkCompile.Margin = new Padding(0, 4, 16, 4);
        _chkContinueNeo.Margin = new Padding(0, 4, 8, 4);
        _chkContinueNeo.ForeColor = Color.FromArgb(180, 210, 255);
        optRow1.Controls.Add(_chkDry);
        optRow1.Controls.Add(_chkCompile);
        optRow1.Controls.Add(_chkContinueNeo);
        options.Controls.Add(optRow1);
        options.Controls.Add(_lblOptionsHint);

        _chkDry.CheckedChanged += (_, _) => UpdateOptionStates();
        _chkContinueNeo.CheckedChanged += (_, _) => { if (!_busy) UpdateModeUi(); };
        _radProject.CheckedChanged += (_, _) => { if (_radProject.Checked) UpdateModeUi(); };
        _radJar.CheckedChanged += (_, _) => { if (_radJar.Checked) UpdateModeUi(); };
        UpdateModeUi();
        UpdateOptionStates();

        var actions = new TableLayoutPanel
        {
            ColumnCount = 4,
            RowCount = 1,
            AutoSize = false,
            Height = 44,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 0, 0, 8)
        };
        actions.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 140f));
        actions.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 140f));
        actions.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 130f));
        actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        actions.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));

        _btnRun.Dock = DockStyle.Fill;
        _btnRun.Margin = new Padding(0, 4, 8, 4);
        _btnRun.BackColor = Color.FromArgb(46, 120, 80);
        _btnRun.FlatAppearance.BorderColor = Color.FromArgb(70, 160, 100);
        _btnRun.Font = new Font("Segoe UI Semibold", 10f);
        _btnRun.Height = 36;

        _btnOpenOut.Dock = DockStyle.Fill;
        _btnOpenOut.Margin = new Padding(0, 4, 8, 4);
        _btnOpenOut.Enabled = false;
        _btnOpenOut.Height = 36;

        _btnClear.Dock = DockStyle.Fill;
        _btnClear.Margin = new Padding(0, 4, 8, 4);
        _btnClear.Height = 36;

        actions.Controls.Add(_btnRun, 0, 0);
        actions.Controls.Add(_btnOpenOut, 1, 0);
        actions.Controls.Add(_btnClear, 2, 0);
        actions.Controls.Add(_progress, 3, 0);

        var logHeader = new Label
        {
            Text = "Log",
            AutoSize = true,
            ForeColor = Color.Gainsboro,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 4, 0, 4)
        };

        _log.Dock = DockStyle.Fill;
        _log.BackColor = Color.FromArgb(22, 24, 28);
        _log.ForeColor = Color.Gainsboro;
        _log.Font = new Font("Consolas", 9f);
        _log.ReadOnly = true;
        _log.BorderStyle = BorderStyle.FixedSingle;
        _log.DetectUrls = false;
        _log.Margin = new Padding(0);

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 8,
            Padding = new Padding(4)
        };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 48f));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));

        header.Dock = DockStyle.Fill;
        modePanel.Dock = DockStyle.Fill;
        paths.Dock = DockStyle.Fill;
        versions.Dock = DockStyle.Fill;
        options.Dock = DockStyle.Fill;
        actions.Dock = DockStyle.Fill;
        logHeader.Dock = DockStyle.Fill;

        root.Controls.Add(header, 0, 0);
        root.Controls.Add(modePanel, 0, 1);
        root.Controls.Add(paths, 0, 2);
        root.Controls.Add(versions, 0, 3);
        root.Controls.Add(options, 0, 4);
        root.Controls.Add(actions, 0, 5);
        root.Controls.Add(logHeader, 0, 6);
        root.Controls.Add(_log, 0, 7);
        Controls.Add(root);

        _btnBrowseIn.Click += (_, _) => BrowseInput();
        _btnBrowseOut.Click += (_, _) =>
        {
            using var dlg = new FolderBrowserDialog
            {
                Description = "Select empty output folder",
                UseDescriptionForTitle = true,
                ShowNewFolderButton = true
            };
            var start = !string.IsNullOrWhiteSpace(_txtOutput.Text)
                ? _txtOutput.Text
                : (!string.IsNullOrWhiteSpace(_txtInput.Text)
                    ? (_radJar.Checked ? Path.GetDirectoryName(_txtInput.Text) : Path.GetDirectoryName(_txtInput.Text))
                    : null);
            if (!string.IsNullOrWhiteSpace(start) && Directory.Exists(start))
                dlg.SelectedPath = start!;
            if (dlg.ShowDialog(this) == DialogResult.OK)
                _txtOutput.Text = dlg.SelectedPath;
        };

        _txtInput.Leave += (_, _) =>
        {
            if (!string.IsNullOrWhiteSpace(_txtInput.Text) && string.IsNullOrWhiteSpace(_txtOutput.Text))
                _txtOutput.Text = SuggestOutputPath(_txtInput.Text);
        };

        _btnRun.Click += (_, _) => StartConversion();
        _btnOpenOut.Click += (_, _) =>
        {
            var p = _txtOutput.Text.Trim();
            if (Directory.Exists(p))
                Process.Start(new ProcessStartInfo("explorer.exe", Quote(p)) { UseShellExecute = true });
            else if (File.Exists(p))
                Process.Start(new ProcessStartInfo("explorer.exe", "/select," + Quote(p)) { UseShellExecute = true });
            else
                MessageBox.Show(this, "Output does not exist yet.", "Open output", MessageBoxButtons.OK, MessageBoxIcon.Information);
        };
        _btnClear.Click += (_, _) => _log.Clear();

        Shown += (_, _) =>
        {
            AppendLog("Ready. Choose Mode A (project) or Mode B (finished .jar).", Color.Gray);
            AppendLog("Mode B uses Vineflower (downloaded once) to decompile, then can scaffold NeoForge 26.2.", Color.Gray);
            AppendLog("Original input is never modified.", Color.LightGreen);
            var tools = ResolveToolsRoot();
            AppendLog($"Tools root: {tools}", Color.DimGray);
            if (!File.Exists(Path.Combine(tools, "Convert-Forge1201-ToNeoForge262.ps1")))
                AppendLog("WARNING: project converter script missing.", Color.Salmon);
            if (!File.Exists(Path.Combine(tools, "Convert-JarToProject.ps1")))
                AppendLog("WARNING: jar decompiler script missing.", Color.Salmon);
        };

        FormClosing += (_, e) =>
        {
            if (_running is { HasExited: false })
            {
                var r = MessageBox.Show(this, "Work is still running. Exit anyway?", "Exit",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
                if (r != DialogResult.Yes)
                {
                    e.Cancel = true;
                    return;
                }
                try { _running.Kill(entireProcessTree: true); } catch { /* ignore */ }
            }
        };
    }

    private void BrowseInput()
    {
        if (_radJar.Checked)
        {
            using var dlg = new OpenFileDialog
            {
                Title = "Select finished mod .jar",
                Filter = "JAR files (*.jar)|*.jar|All files (*.*)|*.*",
                CheckFileExists = true
            };
            if (!string.IsNullOrWhiteSpace(_txtInput.Text) && File.Exists(_txtInput.Text))
                dlg.FileName = _txtInput.Text;
            if (dlg.ShowDialog(this) == DialogResult.OK)
            {
                _txtInput.Text = dlg.FileName;
                if (string.IsNullOrWhiteSpace(_txtOutput.Text) || _txtOutput.Text.Contains("-decompiled", StringComparison.OrdinalIgnoreCase) || _txtOutput.Text.Contains("-26.2", StringComparison.OrdinalIgnoreCase))
                    _txtOutput.Text = SuggestOutputPath(dlg.FileName);
            }
        }
        else
        {
            using var dlg = new FolderBrowserDialog
            {
                Description = "Select Forge 1.20.1 / source project folder",
                UseDescriptionForTitle = true,
                ShowNewFolderButton = false
            };
            if (!string.IsNullOrWhiteSpace(_txtInput.Text) && Directory.Exists(_txtInput.Text))
                dlg.SelectedPath = _txtInput.Text;
            if (dlg.ShowDialog(this) == DialogResult.OK)
            {
                _txtInput.Text = dlg.SelectedPath;
                if (string.IsNullOrWhiteSpace(_txtOutput.Text) || _txtOutput.Text.Contains("-26.2", StringComparison.OrdinalIgnoreCase))
                    _txtOutput.Text = SuggestOutputPath(dlg.SelectedPath);
            }
        }
    }

    private void UpdateModeUi()
    {
        if (_radJar.Checked)
        {
            _lblInput.Text = "Input .jar";
            _btnRun.Text = (_chkContinueNeo.Checked && !_chkDry.Checked) ? "Jar → 26.2" : "Decompile";
            _chkContinueNeo.Visible = true;
            if (!_chkDry.Checked)
            {
                _lblOptionsHint.Text = "JAR mode: Vineflower decompile → src project; optional NeoForge scaffold.";
                _lblOptionsHint.ForeColor = Color.FromArgb(160, 170, 180);
            }
        }
        else
        {
            _lblInput.Text = "Input project";
            _btnRun.Text = "Convert";
            _chkContinueNeo.Visible = false;
            if (!_chkDry.Checked)
            {
                _lblOptionsHint.Text = "Project mode: Forge 1.20.1 source tree → NeoForge 26.2 scaffold.";
                _lblOptionsHint.ForeColor = Color.FromArgb(160, 170, 180);
            }
        }
        if (!_busy)
            _chkContinueNeo.Enabled = _radJar.Checked && !_chkDry.Checked;
    }

    private static Label FieldLabel(string text) => new()
    {
        Text = text,
        AutoSize = true,
        ForeColor = Color.Gainsboro,
        Anchor = AnchorStyles.Left,
        Margin = new Padding(0, 10, 8, 4)
    };

    private static Panel LabeledField(string label, TextBox box, int boxWidth, string defaultText)
    {
        var p = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Margin = new Padding(0, 2, 16, 2)
        };
        p.Controls.Add(new Label
        {
            Text = label,
            AutoSize = true,
            ForeColor = Color.Gainsboro,
            Margin = new Padding(0, 8, 8, 0)
        });
        box.Width = boxWidth;
        box.Height = 26;
        box.Margin = new Padding(0, 4, 0, 4);
        if (!string.IsNullOrEmpty(defaultText))
            box.Text = defaultText;
        p.Controls.Add(box);
        return p;
    }

    private void UpdateOptionStates()
    {
        var dry = _chkDry.Checked;
        if (dry)
        {
            _chkCompile.Checked = false;
            _lblOptionsHint.Text = "Dry run: preview only — no files written.";
            _lblOptionsHint.ForeColor = Color.Khaki;
        }

        if (!_busy)
        {
            _chkDry.Enabled = true;
            _chkCompile.Enabled = !dry;
            _chkContinueNeo.Enabled = _radJar.Checked && !dry;
            _radProject.Enabled = true;
            _radJar.Enabled = true;
        }

        if (!dry)
            UpdateModeUi();
    }

    private static TextBox NewTextBox() => new()
    {
        BackColor = Color.FromArgb(45, 48, 56),
        ForeColor = Color.White,
        BorderStyle = BorderStyle.FixedSingle
    };

    private static CheckBox NewCheck(string text, bool isChecked) => new()
    {
        Text = text,
        Checked = isChecked,
        AutoSize = true,
        ForeColor = Color.Gainsboro
    };

    private static Button NewButton(string text, int minWidth = 100) => new()
    {
        Text = text,
        FlatStyle = FlatStyle.Flat,
        BackColor = Color.FromArgb(60, 64, 78),
        ForeColor = Color.White,
        Height = 32,
        MinimumSize = new Size(minWidth, 32),
        AutoSize = false,
        Cursor = Cursors.Hand,
        FlatAppearance = { BorderColor = Color.FromArgb(90, 96, 112) }
    };

    private static string Quote(string path) => path.Contains(' ') ? $"\"{path}\"" : path;

    private string SuggestOutputPath(string inputPath)
    {
        try
        {
            if (_radJar.Checked)
            {
                var full = Path.GetFullPath(inputPath.Trim());
                var name = Path.GetFileNameWithoutExtension(full);
                var parent = Path.GetDirectoryName(full)!;
                if (_chkContinueNeo.Checked && !_chkDry.Checked)
                {
                    var candidate = Path.Combine(parent, name + "-26.2");
                    var i = 2;
                    while (Directory.Exists(candidate))
                    {
                        candidate = Path.Combine(parent, $"{name}-26.2-{i}");
                        i++;
                    }
                    return candidate;
                }
                else
                {
                    var candidate = Path.Combine(parent, name + "-decompiled");
                    var i = 2;
                    while (Directory.Exists(candidate))
                    {
                        candidate = Path.Combine(parent, $"{name}-decompiled-{i}");
                        i++;
                    }
                    return candidate;
                }
            }
            else
            {
                var full = Path.GetFullPath(inputPath.Trim());
                var name = Path.GetFileName(full.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
                var parent = Path.GetDirectoryName(full)!;
                var candidate = Path.Combine(parent, name + "-26.2");
                var i = 2;
                while (Directory.Exists(candidate))
                {
                    candidate = Path.Combine(parent, $"{name}-26.2-{i}");
                    i++;
                }
                return candidate;
            }
        }
        catch
        {
            return "";
        }
    }

    private static string ResolveToolsRoot()
    {
        var baseDir = AppContext.BaseDirectory;
        var candidates = new[]
        {
            Path.Combine(baseDir, "tools"),
            baseDir,
            Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", ".."))
        };
        foreach (var c in candidates)
        {
            if (File.Exists(Path.Combine(c, "Convert-Forge1201-ToNeoForge262.ps1"))
                || File.Exists(Path.Combine(c, "Convert-JarToProject.ps1")))
                return c;
        }
        return Path.Combine(baseDir, "tools");
    }

    private static bool LooksLikeModProject(string path)
    {
        if (!Directory.Exists(path)) return false;
        if (Directory.Exists(Path.Combine(path, "src"))) return true;
        if (File.Exists(Path.Combine(path, "build.gradle"))) return true;
        if (File.Exists(Path.Combine(path, "gradle.properties"))) return true;
        return false;
    }

    private void SetBusy(bool busy)
    {
        _busy = busy;
        _btnRun.Enabled = !busy;
        _btnBrowseIn.Enabled = !busy;
        _btnBrowseOut.Enabled = !busy;
        _txtInput.Enabled = !busy;
        _txtOutput.Enabled = !busy;
        _txtSource.Enabled = !busy;
        _txtNeo.Enabled = !busy;
        _txtMc.Enabled = !busy;
        _txtGecko.Enabled = !busy;
        _radProject.Enabled = !busy;
        _radJar.Enabled = !busy;
        _progress.Style = busy ? ProgressBarStyle.Marquee : ProgressBarStyle.Continuous;
        _progress.MarqueeAnimationSpeed = busy ? 30 : 0;
        if (!busy) _progress.Value = 0;
        Cursor = busy ? Cursors.WaitCursor : Cursors.Default;

        if (busy)
        {
            _chkCompile.Enabled = false;
            _chkDry.Enabled = false;
            _chkContinueNeo.Enabled = false;
        }
        else
        {
            UpdateOptionStates();
        }
    }

    private void AppendLog(string text, Color color)
    {
        if (IsDisposed) return;
        if (InvokeRequired)
        {
            BeginInvoke(() => AppendLog(text, color));
            return;
        }
        _log.SelectionStart = _log.TextLength;
        _log.SelectionLength = 0;
        _log.SelectionColor = color;
        _log.AppendText(text + Environment.NewLine);
        _log.ScrollToCaret();
    }

    private void StartConversion()
    {
        var inputPath = _txtInput.Text.Trim();
        var outputPath = _txtOutput.Text.Trim();
        var neo = string.IsNullOrWhiteSpace(_txtNeo.Text) ? "26.2.0.32-beta" : _txtNeo.Text.Trim();
        var mc = string.IsNullOrWhiteSpace(_txtMc.Text) ? "26.2" : _txtMc.Text.Trim();
        var gecko = string.IsNullOrWhiteSpace(_txtGecko.Text) ? "5.5.3" : _txtGecko.Text.Trim();
        var source = _txtSource.Text.Trim();
        var jarMode = _radJar.Checked;

        if (string.IsNullOrWhiteSpace(inputPath))
        {
            MessageBox.Show(this, jarMode ? "Choose an input .jar file." : "Choose an input project folder.",
                "Missing input", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        if (jarMode)
        {
            if (!File.Exists(inputPath))
            {
                MessageBox.Show(this, $"JAR not found:\n{inputPath}", "Invalid input", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
        }
        else
        {
            if (!Directory.Exists(inputPath))
            {
                MessageBox.Show(this, $"Input folder does not exist:\n{inputPath}", "Invalid input", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            if (!LooksLikeModProject(inputPath))
            {
                var r = MessageBox.Show(this,
                    "This folder does not look like a mod project (no src/, build.gradle, or gradle.properties).\nContinue anyway?",
                    "Confirm", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                if (r != DialogResult.Yes) return;
            }
        }
        if (string.IsNullOrWhiteSpace(outputPath))
        {
            MessageBox.Show(this, "Choose an output folder.", "Missing output", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var inFull = Path.GetFullPath(inputPath);
        var outFull = Path.GetFullPath(outputPath);
        if (!jarMode && string.Equals(inFull.TrimEnd('\\'), outFull.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
        {
            MessageBox.Show(this, "Output folder must be different from the input folder.", "Invalid output",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        if (Directory.Exists(outFull) && !_chkDry.Checked)
        {
            if (Directory.EnumerateFileSystemEntries(outFull).Any())
            {
                MessageBox.Show(this,
                    "Output folder already exists and is not empty.\nChoose an empty or new folder.\n\n" + outFull,
                    "Output not empty", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
        }

        var toolsRoot = ResolveToolsRoot();
        string script;
        var args = new List<string> { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File" };

        if (jarMode)
        {
            if (_chkContinueNeo.Checked && !_chkDry.Checked)
            {
                script = Path.Combine(toolsRoot, "Convert-OldJarToNeoForge262.ps1");
                if (!File.Exists(script))
                {
                    MessageBox.Show(this, "Missing Convert-OldJarToNeoForge262.ps1 under:\n" + toolsRoot,
                        "Missing tools", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }
                args.Add(Quote(script));
                args.AddRange(new[] { "-JarPath", Quote(inFull), "-OutputPath", Quote(outFull),
                    "-MinecraftVersion", Quote(mc), "-NeoVersion", Quote(neo), "-GeckoLibVersion", Quote(gecko) });
                if (!string.IsNullOrWhiteSpace(source) && !source.Equals("Auto-detect", StringComparison.OrdinalIgnoreCase))
                    args.AddRange(new[] { "-SourceVersion", Quote(source) });
                if (_chkCompile.Checked) args.Add("-Compile");
            }
            else
            {
                script = Path.Combine(toolsRoot, "Convert-JarToProject.ps1");
                if (!File.Exists(script))
                {
                    MessageBox.Show(this, "Missing Convert-JarToProject.ps1 under:\n" + toolsRoot,
                        "Missing tools", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }
                args.Add(Quote(script));
                args.AddRange(new[] { "-JarPath", Quote(inFull), "-OutputPath", Quote(outFull),
                    "-MinecraftVersion", Quote(mc), "-NeoVersion", Quote(neo) });
                if (!string.IsNullOrWhiteSpace(source) && !source.Equals("Auto-detect", StringComparison.OrdinalIgnoreCase))
                    args.AddRange(new[] { "-SourceVersion", Quote(source) });
                if (_chkDry.Checked) args.Add("-DryRun");
            }
        }
        else
        {
            script = Path.Combine(toolsRoot, "Convert-Forge1201-ToNeoForge262.ps1");
            if (!File.Exists(script))
            {
                MessageBox.Show(this, "Missing Convert-Forge1201-ToNeoForge262.ps1 under:\n" + toolsRoot,
                    "Missing tools", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            args.Add(Quote(script));
            args.AddRange(new[]
            {
                "-Path", Quote(inFull),
                "-OutputPath", Quote(outFull),
                "-MinecraftVersion", Quote(mc),
                "-NeoVersion", Quote(neo),
                "-GeckoLibVersion", Quote(gecko)
            });
            if (_chkDry.Checked) args.Add("-DryRun");
            if (!_chkDry.Checked && _chkCompile.Checked) args.Add("-Compile");
            if (!string.IsNullOrWhiteSpace(source) && !source.Equals("Auto-detect", StringComparison.OrdinalIgnoreCase))
                args.AddRange(new[] { "-SourceVersion", Quote(source) });
        }

        _log.Clear();
        AppendLog("RB Legacy Java Converter", Color.White);
        AppendLog(jarMode ? "Mode  : JAR decompile pipeline" : "Mode  : Project convert", Color.LightSkyBlue);
        AppendLog($"Input : {inFull}", Color.LightSkyBlue);
        AppendLog($"Output: {outFull}", Color.LightGreen);
        AppendLog($"Minecraft {mc} / NeoForge {neo} / GeckoLib {gecko}", Color.Khaki);
        AppendLog($"Source version: {(string.IsNullOrWhiteSpace(source) ? "Auto-detect" : source)}", Color.Khaki);
        AppendLog($"Tools : {toolsRoot}", Color.DimGray);
        AppendLog($"Script: {Path.GetFileName(script)}", Color.DimGray);
        if (_chkCompile.Checked)
            AppendLog("Note  : Compile is diagnostic only. Scaffold success does not require a green build.", Color.Khaki);
        if (_chkDry.Checked)
            AppendLog("Dry run: preview only", Color.Khaki);
        AppendLog("----------------------------------------", Color.Gray);
        AppendLog("Starting...", Color.Gainsboro);

        SetBusy(true);
        _lastOutput = outFull;
        _btnOpenOut.Enabled = false;

        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = string.Join(" ", args),
            WorkingDirectory = toolsRoot,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };

        var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
        proc.OutputDataReceived += (_, e) =>
        {
            if (string.IsNullOrEmpty(e.Data)) return;
            var color = Color.Gainsboro;
            if (e.Data.Contains("WARN", StringComparison.OrdinalIgnoreCase) || e.Data.Contains("warning", StringComparison.OrdinalIgnoreCase))
                color = Color.Gold;
            else if (e.Data.Contains("error", StringComparison.OrdinalIgnoreCase) || e.Data.Contains("FAIL", StringComparison.OrdinalIgnoreCase) || e.Data.Contains("Exception", StringComparison.OrdinalIgnoreCase))
                color = Color.Salmon;
            else if (e.Data.Contains("==>") || e.Data.Contains("SUCCESS") || e.Data.Contains("complete") || e.Data.Contains("Copied") || e.Data.Contains("unchanged"))
                color = Color.PaleGreen;
            AppendLog(e.Data, color);
        };
        proc.ErrorDataReceived += (_, e) =>
        {
            if (!string.IsNullOrEmpty(e.Data))
                AppendLog(e.Data, Color.Salmon);
        };

        try
        {
            if (!proc.Start())
                throw new InvalidOperationException("Failed to start PowerShell.");
            proc.BeginOutputReadLine();
            proc.BeginErrorReadLine();
            _running = proc;
        }
        catch (Exception ex)
        {
            SetBusy(false);
            AppendLog("Failed to start: " + ex.Message, Color.Salmon);
            MessageBox.Show(this, ex.Message, "Launch failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        _pollTimer?.Stop();
        _pollTimer?.Dispose();
        _pollTimer = new System.Windows.Forms.Timer { Interval = 250 };
        _pollTimer.Tick += (_, _) =>
        {
            if (_running is null || !_running.HasExited) return;
            _pollTimer.Stop();
            _pollTimer.Dispose();
            _pollTimer = null;

            var code = _running.ExitCode;
            SetBusy(false);
            AppendLog("----------------------------------------", Color.Gray);

            // Scaffold may succeed even if a diagnostic compile left a non-zero code
            // (older tool scripts, or Gradle writing to stderr under PowerShell).
            var scaffoldOk = !_chkDry.Checked
                && !string.IsNullOrWhiteSpace(_lastOutput)
                && (File.Exists(Path.Combine(_lastOutput, "LEGACY_MIGRATION_REPORT.md"))
                    || File.Exists(Path.Combine(_lastOutput, "DECOMPILE_REPORT.md"))
                    || File.Exists(Path.Combine(_lastOutput, "build.gradle")));

            if (code == 0 || scaffoldOk)
            {
                if (code == 0)
                    AppendLog("Finished successfully (exit 0).", Color.LightGreen);
                else
                {
                    AppendLog($"Process exit code {code}; the output scaffold was created but the requested build did not complete.", Color.Gold);
                    AppendLog("Partial result only: repair the reported Gradle/Java errors before installing a JAR.", Color.Gold);
                    if (File.Exists(Path.Combine(_lastOutput, "compile-errors.log")))
                        AppendLog("See compile-errors.log in the output folder for Java/API issues.", Color.Khaki);
                }
                if (!_chkDry.Checked)
                {
                    AppendLog("Output: " + _lastOutput, Color.LightGreen);
                    _btnOpenOut.Enabled = true;
                }
            }
            else
            {
                AppendLog($"Failed with exit code {code}.", Color.Salmon);
            }
            try { _running.Dispose(); } catch { /* ignore */ }
            _running = null;
        };
        _pollTimer.Start();
    }
}
