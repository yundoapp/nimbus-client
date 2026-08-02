const legacyDesktopCorePort = 17078;
const yundoDevDesktopCorePort = 17179;

int resolveDesktopCorePort(String baseDirectoryPath) {
  if (baseDirectoryPath.contains('app.yundo.client.rebuild.dev')) {
    return yundoDevDesktopCorePort;
  }
  return legacyDesktopCorePort;
}
