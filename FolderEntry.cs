namespace NelCapeTown.ExplorerOrchestrator.App;

public class FolderEntry
{
    public string Path { get; set; } = string.Empty;

    public string Name
    {
        get
        {
            var trimmed = Path.TrimEnd(System.IO.Path.DirectorySeparatorChar,
                                       System.IO.Path.AltDirectorySeparatorChar);
            return System.IO.Path.GetFileName(trimmed) is { Length: > 0 } name ? name : trimmed;
        }
    }
}
