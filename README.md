# AotMsixRepro: NativeAOT single-project MSIX publish on the .NET 11 SDK

A minimal WinUI 3 app (Windows App SDK 2.5.1, `PublishAot`, single-project
MSIX). It shows two ways the .NET 11 SDK's optimized NativeAOT publish
breaks `dotnet publish -p:GenerateAppxPackageOnBuild=true`. Since
[dotnet/sdk#54515](https://github.com/dotnet/sdk/issues/54515),
`UseOptimizedPublish` is on by default for `PublishAot`, and publish runs
`PrepareForBuild; PrepareResources; Compile` instead of the full `Build`.

1. `PrepareResources` runs before `ResolveReferences`, so the WinUI XAML
   compiler (`MarkupCompilePass1`) gets no references and fails with
   `WMC1007`. This is
   [dotnet/sdk#56645](https://github.com/dotnet/sdk/issues/56645).
2. The MSIX tooling generates `resources.pri` and the package from
   `PrepareForRun`, which the optimized path never runs. From a clean tree,
   publish fails with `MSB3030` because `resources.pri` is missing. With a
   stale `resources.pri` in `bin\`, it exits 0 and produces no `.msix`.

Reported as
[microsoft/WindowsAppSDK#6897](https://github.com/microsoft/WindowsAppSDK/issues/6897)
(the MSIX tooling's skipped `PrepareForRun`) and
[on dotnet/sdk#56645](https://github.com/dotnet/sdk/issues/56645#issuecomment-6427659922)
(the `WMC1007` ordering).

## Requirements

- Windows x64 and PowerShell 7
- .NET SDK `11.0.100-rc.3.26522.148`, pinned in `global.json`. Optimized
  publish is the default from RC2.
- Visual Studio or Build Tools with the **Desktop development with C++**
  workload, for the NativeAOT linker

## Run

```powershell
.\repro.ps1
.\repro.ps1 -MsixToolingVersion 1.7.261008100   # try a newer MSIX tooling package
```

Each case publishes into `out\<case>` and keeps its log in
`out\<case>\publish.log`. Every case starts from an empty `bin\` and `obj\`,
except the last, which reuses the control case's build. Both workarounds are
in `AotMsixRepro.csproj`, each behind its own property.

## Observed

With SDK 11.0.100-rc.3.26522.148 and MSIX tooling 1.7.251221100 (from
Windows App SDK 2.5.1):

| Case | Extra properties | Exit code | Error | Package |
|---|---|---|---|---|
| default | none | 1 | `WMC1007` | none |
| FixXamlReferences | `-p:FixXamlReferences=true` | 1 | `MSB3030` (`resources.pri`) | none |
| both fixes | `-p:FixXamlReferences=true -p:FixMsixPackaging=true` | 0 | none | `AotMsixRepro_1.0.0.0_x64.msix` |
| UseOptimizedPublish=false | `-p:UseOptimizedPublish=false` | 0 | none | `AotMsixRepro_1.0.0.0_x64.msix` |
| FixXamlReferences, after a full build | `-p:FixXamlReferences=true`, `bin\` and `obj\` kept | 0 | none | **none** |

The "both fixes" package matches the `UseOptimizedPublish=false` package
entry for entry, by name and size. `.\repro.ps1 -MsixToolingVersion
1.7.261008100`, the latest stable MSIX tooling, gives the same results.

The project sets `DebugType=none` to avoid an unrelated `APPX1101` duplicate
`.pdb` error
([microsoft/WindowsAppSDK#6884](https://github.com/microsoft/WindowsAppSDK/issues/6884)),
which happens with or without optimized publish.
