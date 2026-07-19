[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
AppName={code:YundoAppName}
UninstallDisplayName={code:YundoAppName}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL={{PUBLISHER_URL}}
AppUpdatesURL={{PUBLISHER_URL}}
DefaultDirName={{INSTALL_DIR_NAME}}
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
WizardStyle=modern
ShowLanguageDialog=auto
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
CloseApplications=force

[Languages]
{% for locale in LOCALES %}
{% if locale == 'ar' %}Name: "arabic"; MessagesFile: "compiler:Languages\\Arabic.isl"{% endif %}
{% if locale == 'en' %}Name: "english"; MessagesFile: "compiler:Default.isl"{% endif %}
{% if locale == 'fa' %}Name: "farsi"; MessagesFile: "compiler:Languages\\Unofficial\\Farsi.isl"{% endif %}
{% if locale == 'hy' %}Name: "armenian"; MessagesFile: "compiler:Languages\\Armenian.isl"{% endif %}
{% if locale == 'bg' %}Name: "bulgarian"; MessagesFile: "compiler:Languages\\Bulgarian.isl"{% endif %}
{% if locale == 'ca' %}Name: "catalan"; MessagesFile: "compiler:Languages\\Catalan.isl"{% endif %}
{% if locale == 'zh' %}Name: "chinesesimplified"; MessagesFile: "compiler:Languages\\ChineseSimplified.isl"{% endif %}
{% if locale == 'zh-CN' %}Name: "chinesesimplified"; MessagesFile: "compiler:Languages\\ChineseSimplified.isl"{% endif %}
{% if locale == 'zh-TW' %}Name: "chinesetraditional"; MessagesFile: "compiler:Languages\\ChineseTraditional.isl"{% endif %}
{% if locale == 'co' %}Name: "corsican"; MessagesFile: "compiler:Languages\\Corsican.isl"{% endif %}
{% if locale == 'cs' %}Name: "czech"; MessagesFile: "compiler:Languages\\Czech.isl"{% endif %}
{% if locale == 'da' %}Name: "danish"; MessagesFile: "compiler:Languages\\Danish.isl"{% endif %}
{% if locale == 'nl' %}Name: "dutch"; MessagesFile: "compiler:Languages\\Dutch.isl"{% endif %}
{% if locale == 'fi' %}Name: "finnish"; MessagesFile: "compiler:Languages\\Finnish.isl"{% endif %}
{% if locale == 'fr' %}Name: "french"; MessagesFile: "compiler:Languages\\French.isl"{% endif %}
{% if locale == 'de' %}Name: "german"; MessagesFile: "compiler:Languages\\German.isl"{% endif %}
{% if locale == 'he' %}Name: "hebrew"; MessagesFile: "compiler:Languages\\Hebrew.isl"{% endif %}
{% if locale == 'is' %}Name: "icelandic"; MessagesFile: "compiler:Languages\\Icelandic.isl"{% endif %}
{% if locale == 'it' %}Name: "italian"; MessagesFile: "compiler:Languages\\Italian.isl"{% endif %}
{% if locale == 'id' %}Name: "indonesian"; MessagesFile: "compiler:Languages\\Unofficial\\Indonesian.isl"{% endif %}
{% if locale == 'ja' %}Name: "japanese"; MessagesFile: "compiler:Languages\\Japanese.isl"{% endif %}
{% if locale == 'no' %}Name: "norwegian"; MessagesFile: "compiler:Languages\\Norwegian.isl"{% endif %}
{% if locale == 'pl' %}Name: "polish"; MessagesFile: "compiler:Languages\\Polish.isl"{% endif %}
{% if locale == 'pt' %}Name: "portuguese"; MessagesFile: "compiler:Languages\\Portuguese.isl"{% endif %}
{% if locale == 'pt-BR' %}Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\\BrazilianPortuguese.isl"{% endif %}
{% if locale == 'ru' %}Name: "russian"; MessagesFile: "compiler:Languages\\Russian.isl"{% endif %}
{% if locale == 'sk' %}Name: "slovak"; MessagesFile: "compiler:Languages\\Slovak.isl"{% endif %}
{% if locale == 'sl' %}Name: "slovenian"; MessagesFile: "compiler:Languages\\Slovenian.isl"{% endif %}
{% if locale == 'es' %}Name: "spanish"; MessagesFile: "compiler:Languages\\Spanish.isl"{% endif %}
{% if locale == 'tr' %}Name: "turkish"; MessagesFile: "compiler:Languages\\Turkish.isl"{% endif %}
{% if locale == 'uk' %}Name: "ukrainian"; MessagesFile: "compiler:Languages\\Ukrainian.isl"{% endif %}
{% endfor %}

[CustomMessages]
english.ServiceInstallFailed=The system acceleration component could not be installed. Restart Windows and run the Yundo installer again as an administrator.
arabic.ServiceInstallFailed=تعذر تثبيت مكوّن تسريع النظام. أعد تشغيل Windows ثم شغّل مثبّت Yundo مرة أخرى بصلاحيات المسؤول.
spanish.ServiceInstallFailed=No se pudo instalar el componente de aceleración del sistema. Reinicia Windows y vuelve a ejecutar el instalador de Yundo como administrador.
farsi.ServiceInstallFailed=مؤلفه شتاب‌دهی سیستم نصب نشد. Windows را راه‌اندازی مجدد کنید و نصب‌کننده Yundo را دوباره با دسترسی مدیر اجرا کنید.
french.ServiceInstallFailed=Le composant d’accélération système n’a pas pu être installé. Redémarrez Windows, puis relancez le programme d’installation de Yundo en tant qu’administrateur.
indonesian.ServiceInstallFailed=Komponen akselerasi sistem tidak dapat dipasang. Mulai ulang Windows lalu jalankan kembali pemasang Yundo sebagai administrator.
brazilianportuguese.ServiceInstallFailed=Não foi possível instalar o componente de aceleração do sistema. Reinicie o Windows e execute novamente o instalador do Yundo como administrador.
russian.ServiceInstallFailed=Не удалось установить системный компонент ускорения. Перезапустите Windows и снова запустите установщик Yundo от имени администратора.
turkish.ServiceInstallFailed=Sistem hızlandırma bileşeni yüklenemedi. Windows’u yeniden başlatın ve Yundo yükleyicisini yönetici olarak tekrar çalıştırın.
chinesesimplified.ServiceInstallFailed=无法安装系统加速组件。请重启 Windows 后，以管理员身份重新运行云渡安装程序。
chinesetraditional.ServiceInstallFailed=無法安裝系統加速元件。請重新啟動 Windows 後，以管理員身分重新執行雲渡安裝程式。

[Tasks]
Name: "launchAtStartup"; Description: "{cm:AutoStartProgram,Yundo}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: {% if LAUNCH_AT_STARTUP != true %}unchecked{% else %}checkedonce{% endif %}
[Files]
Source: "{{SOURCE_DIR}}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\\{code:YundoAppName}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\\{code:YundoAppName}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; IconFilename: "{app}\\{{EXECUTABLE_NAME}}"
Name: "{userstartup}\\{code:YundoAppName}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; WorkingDir: "{app}"; Tasks: launchAtStartup
[Run]
Filename: "{app}\\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,Yundo}"; Flags: runasoriginaluser nowait postinstall skipifsilent

[UninstallRun]
Filename: "{app}\\YundoService.exe"; Parameters: "tunnel uninstall"; Flags: runhidden waituntilterminated; RunOnceId: "RemoveYundoAccelerationService"

[InstallDelete]
Type: files; Name: "{autoprograms}\\Yundo.lnk"
Type: files; Name: "{autoprograms}\\云渡.lnk"
Type: files; Name: "{autodesktop}\\Yundo.lnk"
Type: files; Name: "{autodesktop}\\云渡.lnk"
Type: files; Name: "{userstartup}\\Yundo.lnk"
Type: files; Name: "{userstartup}\\云渡.lnk"

[Code]
function YundoAppName(Param: String): String;
var
  LanguageId: Integer;
begin
  LanguageId := GetUILanguage;
  if (LanguageId = $0804) or (LanguageId = $1004) then
    Result := '云渡'
  else if (LanguageId = $0404) or (LanguageId = $0C04) or
    (LanguageId = $1404) then
    Result := '雲渡'
  else
    Result := 'Yundo';
end;

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\Yundo\Yundo"

[Code]
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  Exec('taskkill', '/F /IM Yundo.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
  Exec('net', 'stop "HiddifyTunnelService"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
  Exec('sc.exe', 'delete "HiddifyTunnelService"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    if (not Exec(ExpandConstant('{app}\\YundoService.exe'), 'tunnel install',
      ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode)) or
      (ResultCode <> 0) then
      RaiseException(CustomMessage('ServiceInstallFailed'));
  end;
end;
