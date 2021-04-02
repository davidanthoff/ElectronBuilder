using Pkg.Artifacts
using Pkg.BinaryPlatforms
using URIParser, FilePaths

pkgname = "ElectronJS"
version = v"9.1.0"
build = 1

build_path = joinpath(@__DIR__, "build")

if ispath(build_path)
    rm(build_path, force=true, recursive=true)
end

mkpath(build_path)

artifact_toml = joinpath(build_path, "Artifacts.toml")

platforms = [
    # glibc Linuces
    Linux(:i686),
    Linux(:x86_64),
    Linux(:aarch64),
    Linux(:armv7l),
    Linux(:powerpc64le),

    # musl Linuces
    Linux(:i686, libc=:musl),
    Linux(:x86_64, libc=:musl),
    Linux(:aarch64, libc=:musl),
    Linux(:armv7l, libc=:musl),

    # BSDs
    MacOS(:x86_64),
    FreeBSD(:x86_64),

    # Windows
    Windows(:i686),
    Windows(:x86_64),
]

mktempdir() do temp_path

    for platform in platforms
        if platform isa Windows && arch(platform)==:x86_64
            download_url = "https://github.com/electron/electron/releases/download/v$version/electron-v$version-win32-x64.zip"
        elseif platform isa Windows && arch(platform)==:i686
            download_url = "https://github.com/electron/electron/releases/download/v$version/electron-v$version-win32-ia32.zip"
        elseif platform isa MacOS
            download_url = "https://github.com/electron/electron/releases/download/v$version/electron-v$version-darwin-x64.zip"
        elseif platform isa Linux && arch(platform)==:x86_64
            download_url = "https://github.com/electron/electron/releases/download/v$version/electron-v$version-linux-x64.zip"
        elseif platform isa Linux && arch(platform)==:armv7l
            download_url = "https://github.com/electron/electron/releases/download/v$version/electron-v$version-linux-armv7l.zip"
        elseif platform isa Linux && arch(platform)==:aarch64
            download_url = "https://github.com/electron/electron/releases/download/v$version/electron-v$version-linux-arm64.zip"
        else
            continue
        end

        download_filename = joinpath(Path(temp_path), Path(basename(Path(URI(download_url).path))))

        download(download_url, download_filename)

        product_hash = create_artifact() do artifact_dir
            download("http://junolab.s3.amazonaws.com/blink/julia.png", joinpath(artifact_dir, "julia.png"))

            if extension(download_filename) == "zip"
                run(Cmd(`unzip $download_filename -d $artifact_dir`))
            else
                run(Cmd(`tar -xvf $download_filename -C $artifact_dir`))
            end

            # Make sure everything is in the root folder
            files = readdir(artifact_dir)
            if length(files)==1
                stuff_to_move = readdir(joinpath(artifact_dir, files[1]))
                for f in stuff_to_move
                    mv(joinpath(artifact_dir, files[1], f), joinpath(artifact_dir, f))
                end
                rm(joinpath(artifact_dir, files[1]), force=true)
            end

            if platform isa MacOS
                cd(artifact_dir) do
                    run(`mv Electron.app Julia.app`)
                    run(`mv Julia.app/Contents/MacOS/Electron Julia.app/Contents/MacOS/Julia`)
                    run(`sed -i.bak 's/Electron/Julia/' Julia.app/Contents/Info.plist`)
                    cp(joinpath(@__DIR__, "res", "julia-icns.icns"), "Julia.app/Contents/Resources/electron.icns", force=true)
                    run(`touch Julia.app`)  # Apparently this is necessary to tell the OS to double-check for the new icons.
                end
            end

            if platform isa Windows
                run(`chmod +x electron.exe`)
            end
        end

        archive_filename = "$pkgname-$version+$(build)-$(triplet(platform)).tar.gz"

        download_hash = archive_artifact(product_hash, joinpath(build_path, archive_filename))

        bind_artifact!(artifact_toml, "electronjs_app", product_hash, platform=platform, force=true, download_info=Tuple[("https://github.com/davidanthoff/ElectronBuilder/releases/download/v$(URIParser.escape(string(version) * "+" * string(build)))/$archive_filename", download_hash)])
    end
end
