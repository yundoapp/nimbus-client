const yundoDesktopCorePort = 17178;
const yundoDevDesktopCorePort = 17179;
const yundoMobileCorePortFront = 17278;
const yundoMobileCorePortBack = 17279;

int resolveDesktopCorePort(String baseDirectoryPath) {
  if (baseDirectoryPath.contains('app.yundo.client.rebuild.dev')) {
    return yundoDevDesktopCorePort;
  }
  return yundoDesktopCorePort;
}
