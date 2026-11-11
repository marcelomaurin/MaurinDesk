unit uDeskProtocol;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  DESK_MAGIC = $4B53444D; // 'MDSK' ($4D, $44, $53, $4B)
  DEFAULT_DESK_PORT = 9876;

  // Packet Types
  PKT_HELLO       = $01;
  PKT_FRAME       = $02; // Header + dados JPEG
  PKT_MOUSE_MOVE  = $10; // NormX: Word, NormY: Word
  PKT_MOUSE_DOWN  = $11; // Button: Byte, NormX: Word, NormY: Word
  PKT_MOUSE_UP    = $12; // Button: Byte, NormX: Word, NormY: Word
  PKT_MOUSE_WHEEL = $13; // Delta: SmallInt
  PKT_KEY_DOWN    = $20; // KeyCode: Word
  PKT_KEY_UP      = $21; // KeyCode: Word
  PKT_PING        = $30;
  PKT_PONG        = $31;
  PKT_CLOSE       = $FF;

type
  { Cabeçalho de cada quadro de vídeo (12 bytes) }
  TFrameHeader = packed record
    FrameId: Cardinal;
    Width: Word;
    Height: Word;
    JpegSize: Cardinal;
  end;

  { Dados do evento de mouse (5 bytes) }
  TMousePacket = packed record
    Button: Byte; // 1=Esq, 2=Dir, 3=Meio
    NormX: Word;  // 0..65535
    NormY: Word;  // 0..65535
  end;

  { Dados do evento de teclado (3 bytes) }
  TKeyPacket = packed record
    KeyCode: Word;
    Reserved: Byte;
  end;

implementation

end.
