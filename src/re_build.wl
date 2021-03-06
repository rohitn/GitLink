(* ::Package:: *)

(* ::Section:: *)
(*dependencies*)


Needs["CCompilerDriver`"]


(* ::Section:: *)
(*gather build data from environment*)


(* 
This section is jenkins-specific for the moment and will be separated from the logic
of the build script as these pieces get abstracted out to a generalized build framework.
This initial implementation will act as boilerplating for the moment. re_build.wl will get
folded into build.wl as soon as this is done. 
*)

env = Association[GetEnvironment[]];
ws = env["WORKSPACE"];
buildPlatform = env["BUILD_PLATFORM"];
creationID = env["CREATIONID"];
job = env["JOB_NAME"];
filesDir = FileNameJoin[{ws, "Files"}];
compilerBin = env["COMPILER_BIN"];
compilerHome = env["COMPILER_HOME"];

(* infer macCompat from MAC_COMPAT *) 
If[StringQ[env["MAC_COMPAT"]],
	macCompat = env["MAC_COMPAT"],
	macCompat = ToString[False];
];

(* infer targetID from JOB_NAME *)
componentName = StringSplit[job, "."][[2]];
targetID = StringSplit[job, "."][[3]];

(* ::Section:: *)
(*component-specific values*)

base = FileNameJoin[{ws, componentName}];
src = FileNames["*.cpp", FileNameJoin[{base, "src"}], Infinity];
srcDirs = Select[FileNames["*", FileNameJoin[{base, "src"}]], DirectoryQ];
cmp = FileNameJoin[{ws, "Components"}];
plat = FileNameJoin[{targetID, buildPlatform}];
extlib = FileNameJoin[{cmp, "libgit2", "0.23.4"}];
libDirs = {FileNameJoin[{extlib, plat}]};
includeDirs = {FileNameJoin[{extlib, "Source", "include"}]};
compileOpts = "";


compileOpts = Switch[$OperatingSystem,
	"Windows", "/MT /EHsc",
	"MacOSX", "-std=c++11 -stdlib=libc++ -mmacosx-version-min=10.9",
	"Unix", "-Wno-deprecated -std=c++11"];
linkerOpts = Switch[$OperatingSystem,
	"Windows", "/NODEFAULTLIB:msvcrt",
	_, ""];
oslibs = Switch[$OperatingSystem,
	"Windows", {"advapi32", "ole32", "rpcrt4", "shlwapi", "user32", "winhttp"},
	"MacOSX", {"ssl", "z", "iconv", "crypto", "curl"},
	"Unix", {"z", "rt", "pthread"}
];
defines = {Switch[$OperatingSystem,
	"Windows", "WIN",
	"MacOSX", "MAC",
	"Unix", "UNIX"]};
If[StringMatchQ[targetID, "*64*"], AppendTo[defines, "SIXTYFOURBIT"]];


destDir = FileNameJoin[{filesDir, "GitLink", "LibraryResources", targetID}];
If[!DirectoryQ[destDir], CreateDirectory[destDir]];


(* ::Section:: *)
(*build library*)

If[!StringMatchQ[macCompat,"True"],
lib = CreateLibrary[src, "gitLink",
	"TargetDirectory"->destDir,
	"TargetSystemID"->targetID,
	"Language"->"C++",
	"CompileOptions"->compileOpts,
	"CompilerName"->compilerBin,
	"CompilerInstallation"->compilerHome,
	"Defines"->defines,
	"LinkerOptions"->linkerOpts,
	"IncludeDirectories"->Flatten[{includeDirs, srcDirs}],
	"LibraryDirectories"->libDirs,
	"Libraries"->Prepend[oslibs, "git2"],
	"ShellOutputFunction"->Print,
	"ShellCommandFunction"->Print
]

(* we should probably terminate if the compile didn't succeed *)
If[lib === $Failed,
	Print["### ERROR: No library produced. Terminating build... ###"];
	Exit[1]
]];


If[$OperatingSystem == "MacOSX" && StringMatchQ[macCompat,"True"],
Module[{mlobjfile,compileOpts=compileOpts},
	mlobjfile = FileNameJoin[{$InstallationDirectory,
		"SystemFiles/Links/MathLink/DeveloperKit/MacOSX-x86-64",
		"CompilerAdditions/mathlink.framework/Versions/4.25/mathlink"}];
	compileOpts = StringReplace[compileOpts, "10.9"->"10.7"] <> " -Xlinker \"" <> mlobjfile <> "\"";
	lib = CreateLibrary[src, "gitLink_10_3",
	"TargetDirectory"->destDir,
	"TargetSystemID"->targetID,
	"Language"->"C++",
	"CompileOptions"->compileOpts,
	"CompilerName"->compilerBin,
	"CompilerInstallation"->compilerHome,
	"Defines"->defines,
	"LinkerOptions"->linkerOpts,
	"IncludeDirectories"->Flatten[{includeDirs, srcDirs}],
	"LibraryDirectories"->libDirs,
	"Libraries"->Prepend[oslibs, "git2"],
	"SystemLibraries"->{},
	"ShellOutputFunction"->Print,
	"ShellCommandFunction"->Print
];

(* we should probably terminate if the compile didn't succeed *)
If[lib === $Failed,
	Print["### ERROR: No library produced. Terminating build... ###"];
	Exit[1]
]]];


(* ::Section:: *)
(*produce artifact*)


(* 
Using CreateArchive only for zip where we don't care about file permissions.
*)

nativeCreateArchive[src_String, dest_String]:=Module[{res},
	res = RunProcess[{"tar", "czf", dest, src}];
	Return[res];
];

arcName = "Files";

arcFormat = If[$OperatingSystem === "Windows",
	"zip",
	"tar.gz"
];

pack := If[arcFormat === "zip",
	CreateArchive,
	nativeCreateArchive
];

arc = arcName<>"."<>arcFormat;

SetDirectory[filesDir];

archived = pack[componentName, FileNameJoin[{ws,arc}]];

ResetDirectory[];

If[archived === $Failed,
	Print["### ERROR: No archive produced. Terminating build... ###"];
	Exit[1]
];


(* ::Section:: *)
(*generate RE metadata*)


Export[FileNameJoin[{ws,"Build.ini"}],
	{
		"# Build.ini",
		"[job]",
		"name: "<>job,
		"url: "<>env["JOB_URL"],
		"[build]",
		"creationid: "<>creationID,
		"number: "<>env["BUILD_NUMBER"],
		"url: "<>env["BUILD_URL"],
		"[artifact]",
		"name: "<>arc
	},
	{"Text", "Lines"}
]
