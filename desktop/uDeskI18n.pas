unit uDeskI18n;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils;

type
  TDeskLanguage = (dlPortuguese, dlEnglish, dlSpanish);

  TDeskStringId = (
    // General & Window
    strAppTitle,
    strAppSubtitle,
    strTabNewConnection,
    strBtnSettings,
    strVersionBadge,
    strBannerTagline,
    strBannerBuild,

    // Left Sidebar (This Desk)
    strThisDeskTitle,
    strThisDeskSubtitle,
    strBtnRegister,
    strStatusNotConnected,
    strStatusRegisteredOnline,
    strStatusServerOnline,
    strStatusServerChanged,
    strStatusCommError,
    strStatusRegisterFirst,

    // Main Card (Remote Desk)
    strRemoteDeskTitle,
    strRemoteDeskSubtitle,
    strTargetHint,
    strBtnConnect,
    strBtnSaveFav,
    strMenuConnect,
    strMenuRemoveFav,

    // Discovery Card
    strDiscoveryTitle,
    strDiscoverySubtitle,
    strDiscoveryServerLabel,

    // Recent Sessions
    strRecentTitle,
    strRecentHint,
    strRecentEmpty,

    // Consent & Active Session
    strIncomingTitle,
    strIncomingAuthOnlyKnown,
    strBtnAcceptControl,
    strBtnAcceptView,
    strBtnReject,
    strActiveSessionActive,
    strBtnEndSession,

    // Log Console
    strLogTitle,
    strBtnTestConn,
    strBtnCopyLog,
    strBtnClearLog,
    strBtnSendLog,

    // Status Bar & Tooltips
    strStatusReady,
    strStatusCommunicating,
    strStatusSessionRequested,
    strStatusSessionStarted,
    strStatusRejected,
    strStatusClosed,

    // Remote Viewer Window
    strViewerActiveConnection,
    strViewerConnectedTo,
    strViewerFitWindow,
    strViewerOriginalSize,
    strViewerFullScreen,
    strViewerExitFullScreen,
    strViewerDisconnect,
    strViewerWaiting,
    strErrConnectionFailed,

    // Dialogs & Settings
    strDialogSettingsTitle,
    strDialogServerPrompt,
    strDialogLanguageTitle,
    strDialogLanguagePrompt,
    strLogSentSuccess,
    strLogSentFailed
  );

procedure SetDeskLanguage(ALang: TDeskLanguage);
function GetDeskLanguage: TDeskLanguage;
function DeskLangToStr(ALang: TDeskLanguage): string;
function StrToDeskLang(const S: string): TDeskLanguage;
function _T(Id: TDeskStringId): string;

implementation

var
  CurrentLanguage: TDeskLanguage = dlPortuguese;

procedure SetDeskLanguage(ALang: TDeskLanguage);
begin
  CurrentLanguage := ALang;
end;

function GetDeskLanguage: TDeskLanguage;
begin
  Result := CurrentLanguage;
end;

function DeskLangToStr(ALang: TDeskLanguage): string;
begin
  case ALang of
    dlPortuguese: Result := 'pt';
    dlEnglish: Result := 'en';
    dlSpanish: Result := 'es';
  else
    Result := 'pt';
  end;
end;

function StrToDeskLang(const S: string): TDeskLanguage;
var
  Low: string;
begin
  Low := LowerCase(Trim(S));
  if (Low = 'en') or (Low = 'en-us') or (Low = 'english') then
    Result := dlEnglish
  else if (Low = 'es') or (Low = 'es-es') or (Low = 'spanish') or (Low = 'español') or (Low = 'espanol') then
    Result := dlSpanish
  else
    Result := dlPortuguese;
end;

function _T(Id: TDeskStringId): string;
begin
  case CurrentLanguage of
    dlEnglish:
      case Id of
        strAppTitle: Result := 'MaurinDesk v0.6.8 — Assisted Remote Connection';
        strAppSubtitle: Result := 'Assisted and secure remote access.';
        strTabNewConnection: Result := 'New Connection';
        strBtnSettings: Result := '⚙ Settings';
        strVersionBadge: Result := '● Software v0.6.8 (Build 2026-11-14)';
        strBannerTagline: Result := 'Assisted and secure remote desktop.';
        strBannerBuild: Result := 'Build 2026-11-14 | Stream Ready';

        strThisDeskTitle: Result := 'This Computer';
        strThisDeskSubtitle: Result := 'Your computer can be accessed at this address.';
        strBtnRegister: Result := 'Register / Get Key';
        strStatusNotConnected: Result := '● Not connected';
        strStatusRegisteredOnline: Result := '● Registered and Online';
        strStatusServerOnline: Result := '● Server Online';
        strStatusServerChanged: Result := '● Server address changed';
        strStatusCommError: Result := '● Communication error';
        strStatusRegisterFirst: Result := 'Register this computer first.';

        strRemoteDeskTitle: Result := 'Remote Computer';
        strRemoteDeskSubtitle: Result := 'Enter the desk key of the computer you want to access.';
        strTargetHint: Result := 'Enter 10-digit remote key';
        strBtnConnect: Result := 'Connect';
        strBtnSaveFav: Result := 'Save Favorite';
        strMenuConnect: Result := 'Connect to this computer';
        strMenuRemoveFav: Result := 'Remove from favorites';

        strDiscoveryTitle: Result := 'Discovery / Server';
        strDiscoverySubtitle: Result := 'Connected to MaurinDesk cloud API. Sessions managed by mutual consent.';
        strDiscoveryServerLabel: Result := 'API: /MaurinDesk/api';

        strRecentTitle: Result := 'RECENT SESSIONS';
        strRecentHint: Result := '• Double click card to connect';
        strRecentEmpty: Result := 'No recent sessions. Enter a desk key and click "Connect" or "Save Favorite".';

        strIncomingTitle: Result := 'Remote connection request received!';
        strIncomingAuthOnlyKnown: Result := 'Authorize only people you trust.';
        strBtnAcceptControl: Result := 'Allow Control';
        strBtnAcceptView: Result := 'View Only';
        strBtnReject: Result := 'Decline';
        strActiveSessionActive: Result := 'Active session.';
        strBtnEndSession: Result := 'End Session';

        strLogTitle: Result := 'CONNECTION & NETWORK LOG';
        strBtnTestConn: Result := 'Test Server';
        strBtnCopyLog: Result := 'Copy Log';
        strBtnClearLog: Result := 'Clear';
        strBtnSendLog: Result := 'Send Diagnostic Log';

        strStatusReady: Result := 'Ready.';
        strStatusCommunicating: Result := 'Communicating with server...';
        strStatusSessionRequested: Result := 'Session requested: ';
        strStatusSessionStarted: Result := 'Session started: ';
        strStatusRejected: Result := 'Request rejected.';
        strStatusClosed: Result := 'Session ended.';

        strViewerActiveConnection: Result := 'MaurinDesk - Active Session: ';
        strViewerConnectedTo: Result := '● Connected to: ';
        strViewerFitWindow: Result := 'Fit to Window';
        strViewerOriginalSize: Result := 'Actual Size (1:1)';
        strViewerFullScreen: Result := 'Full Screen';
        strViewerExitFullScreen: Result := 'Exit Full Screen';
        strViewerDisconnect: Result := 'Disconnect';
        strViewerWaiting: Result := 'Waiting for remote screen transmission...';
        strErrConnectionFailed: Result := 'Failed to connect to remote host.';

        strDialogSettingsTitle: Result := 'MaurinDesk Configuration';
        strDialogServerPrompt: Result := 'Server API URL:';
        strDialogLanguageTitle: Result := 'Language Selection';
        strDialogLanguagePrompt: Result := 'Choose language: pt (Português), en (English), es (Español):';
        strLogSentSuccess: Result := '[DIAGNOSTIC] Error log successfully sent to server (ID: ';
        strLogSentFailed: Result := '[DIAGNOSTIC] Failed to send log to server: ';
      else
        Result := '';
      end;

    dlSpanish:
      case Id of
        strAppTitle: Result := 'MaurinDesk v0.6.8 — Conexión Remota Asistida';
        strAppSubtitle: Result := 'Acceso remoto asistido y seguro.';
        strTabNewConnection: Result := 'Nueva Conexión';
        strBtnSettings: Result := '⚙ Configuración';
        strVersionBadge: Result := '● Software v0.6.8 (Build 2026-11-14)';
        strBannerTagline: Result := 'Acceso remoto asistido y seguro.';
        strBannerBuild: Result := 'Build 2026-11-14 | Stream Activo';

        strThisDeskTitle: Result := 'Este Equipo';
        strThisDeskSubtitle: Result := 'Su equipo puede ser accedido a través de esta clave.';
        strBtnRegister: Result := 'Registrar / Obtener Clave';
        strStatusNotConnected: Result := '● Desconectado';
        strStatusRegisteredOnline: Result := '● Registrado y En Línea';
        strStatusServerOnline: Result := '● Servidor En Línea';
        strStatusServerChanged: Result := '● Servidor modificado';
        strStatusCommError: Result := '● Error de comunicación';
        strStatusRegisterFirst: Result := 'Registre este equipo primero.';

        strRemoteDeskTitle: Result := 'Equipo Remoto';
        strRemoteDeskSubtitle: Result := 'Introduzca la clave del equipo al que desea acceder.';
        strTargetHint: Result := 'Introduzca la clave de 10 dígitos';
        strBtnConnect: Result := 'Conectar';
        strBtnSaveFav: Result := 'Guardar Favorito';
        strMenuConnect: Result := 'Conectar a este equipo';
        strMenuRemoveFav: Result := 'Eliminar de favoritos';

        strDiscoveryTitle: Result := 'Descubrimiento / Servidor';
        strDiscoverySubtitle: Result := 'Conectado a la API MaurinDesk en la nube. Sesiones con consentimiento.';
        strDiscoveryServerLabel: Result := 'API: /MaurinDesk/api';

        strRecentTitle: Result := 'SESIONES RECIENTES';
        strRecentHint: Result := '• Doble clic en la tarjeta para conectar';
        strRecentEmpty: Result := 'No hay sesiones recientes. Ingrese una clave y haga clic en "Conectar" o "Guardar Favorito".';

        strIncomingTitle: Result := '¡Solicitud de conexión remota recibida!';
        strIncomingAuthOnlyKnown: Result := 'Autorice sólo a personas de su confianza.';
        strBtnAcceptControl: Result := 'Permitir Control';
        strBtnAcceptView: Result := 'Sólo Ver';
        strBtnReject: Result := 'Rechazar';
        strActiveSessionActive: Result := 'Sesión activa.';
        strBtnEndSession: Result := 'Cerrar Sesión';

        strLogTitle: Result := 'REGISTRO DE CONEXIÓN Y RED (LOG)';
        strBtnTestConn: Result := 'Probar Servidor';
        strBtnCopyLog: Result := 'Copiar Log';
        strBtnClearLog: Result := 'Limpiar';
        strBtnSendLog: Result := 'Enviar Log de Error';

        strStatusReady: Result := 'Listo.';
        strStatusCommunicating: Result := 'Comunicando con el servidor...';
        strStatusSessionRequested: Result := 'Sesión solicitada: ';
        strStatusSessionStarted: Result := 'Sesión iniciada: ';
        strStatusRejected: Result := 'Solicitud rechazada.';
        strStatusClosed: Result := 'Sesión cerrada.';

        strViewerActiveConnection: Result := 'MaurinDesk - Sesión Activa: ';
        strViewerConnectedTo: Result := '● Conectado a: ';
        strViewerFitWindow: Result := 'Ajustar a Ventana';
        strViewerOriginalSize: Result := 'Tamaño Real (1:1)';
        strViewerFullScreen: Result := 'Pantalla Completa';
        strViewerExitFullScreen: Result := 'Salir de Pantalla Completa';
        strViewerDisconnect: Result := 'Desconectar';
        strViewerWaiting: Result := 'Esperando transmisión de pantalla remota...';
        strErrConnectionFailed: Result := 'Fallo al conectar con el equipo remoto.';

        strDialogSettingsTitle: Result := 'Configuración MaurinDesk';
        strDialogServerPrompt: Result := 'URL de la API del Servidor:';
        strDialogLanguageTitle: Result := 'Selección de Idioma';
        strDialogLanguagePrompt: Result := 'Elija idioma: pt (Português), en (English), es (Español):';
        strLogSentSuccess: Result := '[DIAGNÓSTICO] Log de error enviado con éxito al servidor (ID: ';
        strLogSentFailed: Result := '[DIAGNÓSTICO] Error al enviar log al servidor: ';
      else
        Result := '';
      end;

  else // dlPortuguese (Default)
    case Id of
      strAppTitle: Result := 'MaurinDesk v0.6.8 — Conexão Remota Assistida';
      strAppSubtitle: Result := 'Acesso remoto assistido e seguro.';
      strTabNewConnection: Result := 'Nova Conexão';
      strBtnSettings: Result := '⚙ Config Servidor';
      strVersionBadge: Result := '● Software v0.6.8 (Build 2026-11-14)';
      strBannerTagline: Result := 'Acesso remoto assistido e seguro.';
      strBannerBuild: Result := 'Build 2026-11-14 | Stream Ativo';

      strThisDeskTitle: Result := 'Este Computador';
      strThisDeskSubtitle: Result := 'Seu computador pode ser acessado por este endereço.';
      strBtnRegister: Result := 'Registrar / Obter Chave';
      strStatusNotConnected: Result := '● Não conectado';
      strStatusRegisteredOnline: Result := '● Registrado e Online';
      strStatusServerOnline: Result := '● Servidor Online';
      strStatusServerChanged: Result := '● Servidor alterado';
      strStatusCommError: Result := '● Erro de comunicação';
      strStatusRegisterFirst: Result := 'Registre esta máquina primeiro.';

      strRemoteDeskTitle: Result := 'Computador Remoto';
      strRemoteDeskSubtitle: Result := 'Informe a chave do computador que você gostaria de acessar.';
      strTargetHint: Result := 'Digite a chave de 10 dígitos';
      strBtnConnect: Result := 'Conectar';
      strBtnSaveFav: Result := 'Salvar Favorito';
      strMenuConnect: Result := 'Conectar a este computador';
      strMenuRemoveFav: Result := 'Remover dos favoritos';

      strDiscoveryTitle: Result := 'Descoberta / Servidor';
      strDiscoverySubtitle: Result := 'Conectado à API MaurinDesk na nuvem. Sessões gerenciadas por consentimento.';
      strDiscoveryServerLabel: Result := 'API: /MaurinDesk/api';

      strRecentTitle: Result := 'SESSÕES RECENTES';
      strRecentHint: Result := '• Duplo clique no cartão para conectar';
      strRecentEmpty: Result := 'Nenhuma sessão recente. Digite uma chave e clique em "Conectar" ou "Salvar Favorito".';

      strIncomingTitle: Result := 'Solicitação de conexão recebida!';
      strIncomingAuthOnlyKnown: Result := 'Autorize apenas quem você conhece.';
      strBtnAcceptControl: Result := 'Permitir Controle';
      strBtnAcceptView: Result := 'Só Visualizar';
      strBtnReject: Result := 'Recusar';
      strActiveSessionActive: Result := 'Sessão ativa.';
      strBtnEndSession: Result := 'Encerrar Sessão';

      strLogTitle: Result := 'REGISTRO DE CONEXÃO E REDE (LOG)';
      strBtnTestConn: Result := 'Testar Conexão';
      strBtnCopyLog: Result := 'Copiar Log';
      strBtnClearLog: Result := 'Limpar';
      strBtnSendLog: Result := 'Enviar Log ao Servidor';

      strStatusReady: Result := 'Pronto.';
      strStatusCommunicating: Result := 'Comunicando com o servidor...';
      strStatusSessionRequested: Result := 'Sessão solicitada: ';
      strStatusSessionStarted: Result := 'Sessão iniciada: ';
      strStatusRejected: Result := 'Pedido recusado.';
      strStatusClosed: Result := 'Sessão encerrada.';

      strViewerActiveConnection: Result := 'MaurinDesk - Conexão Ativa: ';
      strViewerConnectedTo: Result := '● Conectado a: ';
      strViewerFitWindow: Result := 'Ajustar à Janela';
      strViewerOriginalSize: Result := 'Tamanho Real (1:1)';
      strViewerFullScreen: Result := 'Tela Cheia';
      strViewerExitFullScreen: Result := 'Sair da Tela Cheia';
      strViewerDisconnect: Result := 'Desconectar';
      strViewerWaiting: Result := 'Aguardando transmissão da tela remota...';
      strErrConnectionFailed: Result := 'Falha ao conectar com o computador remoto.';

      strDialogSettingsTitle: Result := 'Configuração MaurinDesk';
      strDialogServerPrompt: Result := 'Endereço da API do Servidor:';
      strDialogLanguageTitle: Result := 'Idioma do Aplicativo';
      strDialogLanguagePrompt: Result := 'Escolha o idioma: pt (Português), en (English), es (Español):';
      strLogSentSuccess: Result := '[DIAGNÓSTICO] Log de erro enviado com sucesso ao servidor (ID: ';
      strLogSentFailed: Result := '[DIAGNÓSTICO] Falha ao enviar log ao servidor: ';
    else
      Result := '';
    end;
  end;
end;

end.