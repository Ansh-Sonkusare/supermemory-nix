{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  glibc,
}:

let
  version = "0.0.8";

  assets = {
    aarch64-darwin = {
      os = "darwin";
      arch = "arm64";
      hash = "sha256-EreBehBe0KnnD5bEYftvjd7V1w6utgNOd0d4wle+14o=";
    };
    x86_64-darwin = {
      os = "darwin";
      arch = "x64";
      hash = "sha256-K1CCH8KwqVLRQx+l2vWvGaNQdIqC4SQqZcSh5ctFO+s=";
    };
    aarch64-linux = {
      os = "linux";
      arch = "arm64";
      hash = "sha256-7rnmKov1lka9eZoF0aKYG5RUE6A2QMOjn08metLSvzc=";
    };
    x86_64-linux = {
      os = "linux";
      arch = "x64";
      hash = "sha256-h/MkM9AXm+gLudihuvusZa9BKDJDQqJ+y4vRp3tVBvM=";
    };
  };

  asset =
    assets.${stdenv.targetPlatform.system}
    or (throw "supermemory-server: unsupported platform ${stdenv.targetPlatform.system}");

  url = "https://github.com/supermemoryai/supermemory/releases/download/server-v${version}/supermemory-server-${asset.os}-${asset.arch}";
in

stdenv.mkDerivation {
  pname = "supermemory-server";
  inherit version;

  src = fetchurl {
    inherit url;
    sha256 = asset.hash;
  };

  dontUnpack = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ glibc ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/supermemory-server
    runHook postInstall
  '';

  meta = with lib; {
    description = "Self-hostable AI memory layer: documents, memories, and hybrid search over a local API";
    homepage = "https://supermemory.ai";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    license = licenses.mit;
    platforms = builtins.attrNames assets;
    mainProgram = "supermemory-server";
  };
}