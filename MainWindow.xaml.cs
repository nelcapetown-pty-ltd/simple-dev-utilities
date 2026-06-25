using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;

namespace NelCapeTown.ExplorerOrchestrator.App;

public partial class MainWindow : Window
{
    private static readonly string SettingsPath = Path.Combine(
        AppContext.BaseDirectory, "folders.json");

    private static readonly string ThemePath = Path.Combine(
        AppContext.BaseDirectory, "theme.txt");

    private bool _isDark = true;

    private static readonly string AhkScriptPath = Path.Combine(
        AppContext.BaseDirectory,
        "OpenFoldersTabbedExplorer.ahk");

    private static readonly string[] AhkExeCandidates =
    [
        @"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe",
        @"C:\Program Files\AutoHotkey\v2\AutoHotkey32.exe",
        @"C:\Program Files\AutoHotkey\AutoHotkey64.exe",
        @"C:\Program Files\AutoHotkey\AutoHotkey.exe",
    ];

    private static readonly string[] DefaultFolders =
    [
        @"E:\src\nelcapetown.com portfolio website\Portfolio Website Artwork & Artefacts",
        @"D:\Obsidian_Parent\DefaultVault",
        @"D:\OneDrive Root\OneDrive - Nel Cape Town\Documents\NelCapeTownPtyLtdDotCom",
        @"D:\Downloads",
        @"\\wsl.localhost\Ubuntu-24.04\home\nel\projects\nelcapetowndotcom",
    ];

    private readonly ObservableCollection<FolderEntry> _folders = [];

    public MainWindow()
    {
        InitializeComponent();
        FolderList.ItemsSource = _folders;
        LoadFolders();
        RefreshEmptyState();
        LoadTheme();
    }

    private void AddFolder_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Select a folder to add",
            Multiselect = true
        };

        if (dialog.ShowDialog(this) != true)
            return;

        foreach (var path in dialog.FolderNames)
        {
            if (!_folders.Any(f => f.Path.Equals(path, StringComparison.OrdinalIgnoreCase)))
                _folders.Add(new FolderEntry { Path = path });
        }

        RefreshEmptyState();
    }

    private void DeleteFolder_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: FolderEntry folder })
        {
            _folders.Remove(folder);
            RefreshEmptyState();
        }
        e.Handled = true;
    }

    private void SaveButton_Click(object sender, RoutedEventArgs e)
    {
        SaveFolders();
    }

    private void OpenFolder_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: FolderEntry folder })
            LaunchExplorer(folder.Path);
    }

    private void OpenAll_Click(object sender, RoutedEventArgs e)
    {
        if (_folders.Count == 0)
            return;

        var ahkExe = AhkExeCandidates.FirstOrDefault(File.Exists);
        if (ahkExe is null)
        {
            MessageBox.Show(
                "AutoHotkey v2 not found. Install it from autohotkey.com.",
                "Explorer Orchestrator", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        if (!File.Exists(AhkScriptPath))
        {
            MessageBox.Show(
                $"AHK script not found at:\n{AhkScriptPath}",
                "Explorer Orchestrator", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var quotedPaths = string.Join(" ", _folders.Select(f => $"\"{f.Path}\""));
        Process.Start(new ProcessStartInfo
        {
            FileName = ahkExe,
            Arguments = $"\"{AhkScriptPath}\" {quotedPaths}",
            UseShellExecute = false
        });
    }

    private static void LaunchExplorer(string path)
    {
        if (Directory.Exists(path))
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"\"{path}\"",
                UseShellExecute = true
            });
    }

    private void LoadFolders()
    {
        if (File.Exists(SettingsPath))
        {
            try
            {
                var list = JsonSerializer.Deserialize<List<FolderEntry>>(File.ReadAllText(SettingsPath));
                if (list is { Count: > 0 })
                {
                    foreach (var f in list)
                        _folders.Add(f);
                    return;
                }
            }
            catch { }
        }

        // JSON missing or empty — seed from hardcoded defaults
        foreach (var path in DefaultFolders)
            _folders.Add(new FolderEntry { Path = path });
    }

    private void SaveFolders()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath)!);
            File.WriteAllText(SettingsPath,
                JsonSerializer.Serialize(_folders.ToList(),
                    new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }

    private void RefreshEmptyState()
    {
        EmptyMessage.Visibility = _folders.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void ThemeToggle_Click(object sender, RoutedEventArgs e)
    {
        _isDark = !_isDark;
        ApplyTheme(_isDark);
        SaveTheme();
    }

    private void LoadTheme()
    {
        if (File.Exists(ThemePath))
            _isDark = File.ReadAllText(ThemePath).Trim() != "light";

        ApplyTheme(_isDark);
    }

    private void SaveTheme()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(ThemePath)!);
            File.WriteAllText(ThemePath, _isDark ? "dark" : "light");
        }
        catch { }
    }

    private void ApplyTheme(bool isDark)
    {
        var r = Application.Current.Resources;

        if (isDark)
        {
            r["ThemeAppBg"]                = Brush("#1E1E1E");
            r["ThemeHeaderBg"]             = Brush("#252525");
            r["ThemeHeaderBorder"]         = Brush("#333333");
            r["ThemePrimaryText"]          = Brush("#FFFFFF");
            r["ThemeSubText"]              = Brush("#606060");
            r["ThemeEmptyText"]            = Brush("#555555");
            r["ThemeCardBg"]               = Brush("#2D2D2D");
            r["ThemeCardBorder"]           = Brush("#3D3D3D");
            r["ThemeCardHoverBg"]          = Brush("#383838");
            r["ThemeCardHoverBorder"]      = Brush("#5A5A5A");
            r["ThemeActionBtnFg"]          = Brush("#FFFFFF");
            r["ThemeActionBtnBg"]          = Brush("#3A3A3A");
            r["ThemeActionBtnBorder"]      = Brush("#555555");
            r["ThemeActionBtnHoverBg"]     = Brush("#4A4A4A");
            r["ThemeActionBtnHoverBorder"] = Brush("#6A6A6A");
            r["ThemeActionBtnPressedBg"]   = Brush("#252525");
            r["ThemeDeleteBtnFg"]          = Brush("#666666");
        }
        else
        {
            r["ThemeAppBg"]                = Brush("#F3F3F3");
            r["ThemeHeaderBg"]             = Brush("#FFFFFF");
            r["ThemeHeaderBorder"]         = Brush("#E0E0E0");
            r["ThemePrimaryText"]          = Brush("#1A1A1A");
            r["ThemeSubText"]              = Brush("#888888");
            r["ThemeEmptyText"]            = Brush("#AAAAAA");
            r["ThemeCardBg"]               = Brush("#FFFFFF");
            r["ThemeCardBorder"]           = Brush("#E0E0E0");
            r["ThemeCardHoverBg"]          = Brush("#F0F0F0");
            r["ThemeCardHoverBorder"]      = Brush("#BDBDBD");
            r["ThemeActionBtnFg"]          = Brush("#1A1A1A");
            r["ThemeActionBtnBg"]          = Brush("#E8E8E8");
            r["ThemeActionBtnBorder"]      = Brush("#CCCCCC");
            r["ThemeActionBtnHoverBg"]     = Brush("#D8D8D8");
            r["ThemeActionBtnHoverBorder"] = Brush("#BBBBBB");
            r["ThemeActionBtnPressedBg"]   = Brush("#C0C0C0");
            r["ThemeDeleteBtnFg"]          = Brush("#999999");
        }

        ThemeToggleButton.Content = isDark ? "Light Theme" : "Dark Theme";
    }

    private static SolidColorBrush Brush(string hex) =>
        new((Color)ColorConverter.ConvertFromString(hex));
}
