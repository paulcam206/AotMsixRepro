using Microsoft.UI.Xaml;

namespace AotMsixRepro;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new Window { Title = "AotMsixRepro" };
        _window.Activate();
    }
}
