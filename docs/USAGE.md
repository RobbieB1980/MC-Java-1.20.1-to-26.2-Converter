# Usage examples

## Convert without compile

```powershell
.\Convert-Forge1201-ToNeoForge262.ps1 `
  -Path "C:\mods\legacy\mymod" `
  -OutputPath "C:\mods\mymod-26.2"
```

## Convert and run the complete build

```powershell
.\Convert-Forge1201-ToNeoForge262.ps1 `
  -Path "C:\mods\legacy\mymod" `
  -OutputPath "C:\mods\mymod-26.2" `
  -Compile
# Success produces an installable JAR in build\libs.
# Failure preserves the scaffold and writes compile-errors.log and COMPILE_REPORT.md.
```

## Finished NeoForge 1.21.x jar → 26.2 scaffold

```powershell
.\Convert-OldJarToNeoForge262.ps1 `
  -JarPath "C:\mods\the_knocker-1.5.2-neoforge-1.21.8.jar" `
  -OutputPath "C:\mods\the_knocker-26.2" `
  -Compile
```

Then fix remaining compile errors if needed and:

```powershell
cd "C:\mods\the_knocker-26.2"
.\gradlew.bat build
# Install build\libs\*.jar only — not the original 1.21.8 jar
```

## Pin NeoForge version

```powershell
.\Convert-Forge1201-ToNeoForge262.ps1 `
  -Path "C:\mods\legacy\mymod" `
  -OutputPath "C:\mods\mymod-26.2" `
  -NeoVersion "26.2.0.66" `
  -ModDevGradleVersion "2.0.144"
```

## Convert with dependency download + recursive port

```powershell
.\Convert-Forge1201-ToNeoForge262.ps1 `
  -Path "C:\mods\legacy\mymod" `
  -OutputPath "C:\mods\mymod-26.2" `
  -DependencyJarDir "C:\mods\legacy\jars" `
  -Compile
# See DEPENDENCY_REPORT.md — official 26.2 jars in libs\, converted required mods in converted-deps\
```

Preview declared dependencies without writing files:

```powershell
.\Convert-Forge1201-ToNeoForge262.ps1 `
  -Path "C:\mods\legacy\mymod" `
  -OutputPath "C:\mods\mymod-26.2" `
  -DryRun
```

