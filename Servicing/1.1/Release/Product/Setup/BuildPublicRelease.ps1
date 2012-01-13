param( $outdir )

if (-not $outdir)
{
    Write-Error "Must provide $outdir"
	exit 1
}

###################################################################
# Build the actual binaries
echo "Building release to $outdir ..."
.\BuildRelease.ps1 $outdir > release_output.txt

###################################################################
# Index symbols

$buildid = $outdir.Substring($outdir.LastIndexOf('\') + 1)

$request = `
"BuildId=$buildid
BuildLabPhone=7058786
BuildRemark=beta
ContactPeople=$env:username;dinov;smortaz
Directory=$outdir\Release\Symbols
Project=TechnicalComputing
Recursive=yes
StatusMail=$env:username;dinov;smortaz
UserName=$env:username
SubmitToArchive=ALL
SubmitToInternet=Yes"

mkdir -force requests
$request | Out-File -Encoding ascii -FilePath request.txt
\\symbols\tools\createrequest.cmd -i request.txt -d .\requests -c -s

[Reflection.Assembly]::Load("CODESIGN.Submitter, Version=3.0.0.4, Culture=neutral, PublicKeyToken=3d8252bd1272440d, processorArchitecture=MSIL")
[Reflection.Assembly]::Load("CODESIGN.PolicyManager, Version=1.0.0.0, Culture=neutral, PublicKeyToken=3d8252bd1272440d, processorArchitecture=MSIL")

#################################################################
# Submit managed binaries

$approvers = "smortaz", "mradmila", "pavaga"

$job = [CODESIGN.Submitter.Job]::Initialize("codesign.gtm.microsoft.com", 9556, $True)
$job.Description = "Python Tools for Visual Studio - managed code"
$job.Keywords = "PTVS; Visual Studion; Python"

$job.SelectCertificate("10006")  # Authenticode
$job.SelectCertificate("67")     # StrongName key

foreach ($approver in $approvers) { $job.AddApprover($approver) }

$files = ("Microsoft.PythonTools.Analysis.dll", 
          "Microsoft.PythonTools.Analyzer.exe", 
          "Microsoft.PythonTools.Attacher.exe", 
          "Microsoft.PythonTools.AttacherX86.exe", 
          "Microsoft.PythonTools.Debugger.dll", 
          "Microsoft.PythonTools.dll", 
          "Microsoft.PythonTools.Hpc.dll", 
          "Microsoft.PythonTools.IronPython.dll", 
          "Microsoft.PythonTools.MpiShim.exe", 
          "Microsoft.PythonTools.Profiling.dll", 
          "Microsoft.VisualStudio.ReplWindow.dll",
          "Microsoft.PythonTools.PyKinect.dll",
          "Microsoft.PythonTools.Pyvot.dll")

foreach ($filename in $files) {
    $fullpath =  "$outdir\Release\Binaries\$filename"
    $job.AddFile($fullpath, "Python Tools for Visual Studio", "http://pytools.codeplex.com", [CODESIGN.JavaPermissionsTypeEnum]::None)
}
$job.Send()

$firstjob = $job

#################################################################
### Submit x86 native binaries

$job = [CODESIGN.Submitter.Job]::Initialize("codesign.gtm.microsoft.com", 9556, $True)
$job.Description = "Python Tools for Visual Studio - managed code"
$job.Keywords = "PTVS; Visual Studion; Python"

$job.SelectCertificate("10006")  # Authenticode

foreach ($approver in $approvers) { $job.AddApprover($approver) }

$files = "PyDebugAttach.dll", "VsPyProf.dll", "PyKinectAudio.dll"

foreach ($filename in $files) {
    $fullpath = "$outdir\Release\Binaries\$filename"
    $job.AddFile($fullpath, "Python Tools for Visual Studio", "http://pytools.codeplex.com", [CODESIGN.JavaPermissionsTypeEnum]::None)
}
$job.Send()
$secondjob = $job

#################################################################
### Submit x64 native binaries

$job = [CODESIGN.Submitter.Job]::Initialize("codesign.gtm.microsoft.com", 9556, $True)
$job.Description = "Python Tools for Visual Studio - managed code"
$job.Keywords = "PTVS; Visual Studion; Python"

$job.SelectCertificate("10006")  # Authenticode

foreach ($approver in $approvers) { $job.AddApprover($approver) }

$files = "PyDebugAttach.dll", "VsPyProf.dll"

foreach ($filename in $files) {
    $fullpath = "$outdir\Release\Binaries\x64\$filename"
    $job.AddFile($fullpath, "Python Tools for Visual Studio", "http://pytools.codeplex.com", [CODESIGN.JavaPermissionsTypeEnum]::None)
}

$job.Send()
$thirdjob = $job

# wait for all 3 jobs to finish being signed...
$jobs = $firstjob, $secondjob, $thirdjob
foreach($job in $jobs) {
    $activity = "Job ID " + $job.JobID + " still processing"
    $percent = 0
    do {
        $files = dir $job.JobCompletionPath
        write-progress -activity $activity -status "Waiting for completion:" -percentcomplete $percent;
        $percent = ($percent + 1) % 100
        sleep -seconds 5
    } while(-not $files);
}

# save binaries to release share
$destpath = "$outdir\Release\SignedBinaries"
mkdir $destpath
# copy files back to binaries
echo 'Completion path', $firstjob.JobCompletionPath

robocopy $firstjob.JobCompletionPath $destpath\
robocopy $secondjob.JobCompletionPath $destpath\
robocopy $thirdjob.JobCompletionPath $destpath\x64\

# copy files back to binaries for re-building the MSI
robocopy $firstjob.JobCompletionPath ..\..\..\binaries\win32\Release\
robocopy $secondjob.JobCompletionPath ..\..\..\binaries\win32\Release\
robocopy $thirdjob.JobCompletionPath ..\..\..\binaries\x64\Release\

# now generate MSI with signed binaries.
$file = Get-Content release_output.txt
foreach($line in $file) {
    if($line.IndexOf('Light.exe') -ne -1) { 
        if($line.IndexOf('Release') -ne -1) { 
            $end = $line.IndexOf('.msm')
            if ($end -eq -1) {
                $end = $line.IndexOf('.msi')
            }
            $start = $line.LastIndexOf('\', $end)
            $targetdir = $line.Substring($start + 1, $end - $start - 1)
            # hacks for mismatched names
            if ($targetdir -eq "IronPythonInterpreterMsm") {
                $targetdir = "IronPythonInterpreter"
            }
            if ($targetdir -eq "PythonProfiler") {
                $targetdir = "PythonProfiling"
            }
            if ($targetdir -eq "PythonHpcSupportMsm") {
                $targetdir = "PythonHpcSupport"
            }
            if ($targetdir -eq "PyvotMsm") {
                $targetdir = "PyVot"
            }
            if ($targetdir -eq "PyKinectMsm") {
                $targetdir = "PyKinect"
            }
            echo $targetdir

            cd $targetdir
            
            Invoke-Expression $line
            
            cd ..
        }
    }
}

$destpath = "$outdir\Release\UnsignedMsi"
mkdir $destpath
move $outdir\Release\PythonToolsInstaller.msi $outdir\Release\UnsignedMsi\PythonToolsInstaller.msi
move $outdir\Release\PyKinectInstaller.msi $outdir\Release\UnsignedMsi\PyKinectInstaller.msi
move $outdir\Release\PyvotInstaller.msi $outdir\Release\UnsignedMsi\PyvotInstaller.msi

$destpath = "$outdir\Release\SignedBinariesUnsignedMsi"
mkdir $destpath
copy  ..\..\..\Binaries\Win32\Release\PythonToolsInstaller.msi $outdir\Release\SignedBinariesUnsignedMsi\PythonToolsInstaller.msi
copy  ..\..\..\Binaries\Win32\Release\PythonToolsInstaller.msi $outdir\Release\PythonToolsInstaller.msi

copy  ..\..\..\Binaries\Win32\Release\PyKinectInstaller.msi $outdir\Release\SignedBinariesUnsignedMsi\PyKinectInstaller.msi
copy  ..\..\..\Binaries\Win32\Release\PyKinectInstaller.msi $outdir\Release\PyKinectInstaller.msi

copy  ..\..\..\Binaries\Win32\Release\PyvotInstaller.msi $outdir\Release\SignedBinariesUnsignedMsi\PyvotInstaller.msi
copy  ..\..\..\Binaries\Win32\Release\PyvotInstaller.msi $outdir\Release\PyvotInstaller.msi

#################################################################
### Now submit the MSI for signing

$job = [CODESIGN.Submitter.Job]::Initialize("codesign.gtm.microsoft.com", 9556, $True)
$job.Description = "Python Tools for Visual Studio - managed code"
$job.Keywords = "PTVS; Visual Studion; Python"

$job.SelectCertificate("10006")  # Authenticode

foreach ($approver in $approvers) { $job.AddApprover($approver) }

$job.AddFile((get-location).Path + "\..\..\..\Binaries\Win32\Release\PythonToolsInstaller.msi", "Python Tools for Visual Studio", "http://pytools.codeplex.com", [CODESIGN.JavaPermissionsTypeEnum]::None)
$job.AddFile((get-location).Path + "\..\..\..\Binaries\Win32\Release\PyKinectInstaller.msi", "Python Tools for Visual Studio - PyKinect", "http://pytools.codeplex.com", [CODESIGN.JavaPermissionsTypeEnum]::None)
$job.AddFile((get-location).Path + "\..\..\..\Binaries\Win32\Release\PyvotInstaller.msi", "Python Tools for Visual Studio - Pyvot", "http://pytools.codeplex.com", [CODESIGN.JavaPermissionsTypeEnum]::None)

$job.Send()

$activity = "Job ID " + $job.JobID + " still processing"
$percent = 0
do {
    $files = dir $job.JobCompletionPath
    write-progress -activity $activity -status "Waiting for completion:" -percentcomplete $percent;
    $percent = ($percent + 1) % 100
    sleep -seconds 5
} while(-not $files);

copy -force "$($job.JobCompletionPath)\PythonToolsInstaller.msi" "$outdir\Release\PTVS 1.1 Beta 1.msi"
copy -force "$($job.JobCompletionPath)\PyKinectInstaller.msi" "$outdir\Release\PTVS 1.1 Beta 1 - PyKinect Sample.msi"
copy -force "$($job.JobCompletionPath)\PyvotInstaller.msi" "$outdir\Release\PTVS 1.1 Beta 1 - Pyvot Sample.msi"