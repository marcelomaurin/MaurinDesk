program capture_regression;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Windows, Classes, SysUtils, Graphics, uScreenCapture;
var
  Bmp: Graphics.TBitmap;
  Jpg: TJPEGImage;
  Decoded: Graphics.TBitmap;
  Stream: TMemoryStream;
  Brush: HBRUSH;
  R: TRect;
  Pixel: TColor;
begin
  try
  Application.Initialize;
  Bmp := Graphics.TBitmap.Create;
  Jpg := TJPEGImage.Create;
  Decoded := Graphics.TBitmap.Create;
  Stream := TMemoryStream.Create;
  try
    Bmp.PixelFormat := pf24bit;
    Bmp.SetSize(64, 64);
    // Same native GDI write used by capture: it bypasses LCL notifications.
    Brush := CreateSolidBrush(RGB(230, 40, 20));
    try
      R := Rect(0, 0, 64, 64);
      if Windows.FillRect(Bmp.Canvas.Handle, R, Brush) = 0 then
        raise Exception.Create('Native GDI fill failed');
    finally
      DeleteObject(Brush);
    end;
    CompressBitmapToJpegStream(Bmp, Stream, 90);
    Stream.Position := 0;
    Jpg.LoadFromStream(Stream);
    Decoded.Assign(Jpg);
    Pixel := ColorToRGB(Decoded.Canvas.Pixels[32, 32]);
    WriteLn('Decoded RGB: ', Red(Pixel), ',', Green(Pixel), ',', Blue(Pixel));
    if (Abs(Integer(Red(Pixel)) - 230) > 10) or
       (Abs(Integer(Green(Pixel)) - 40) > 10) or
       (Abs(Integer(Blue(Pixel)) - 20) > 10) then
      raise Exception.Create('Native captured pixels lost during JPEG encoding');
    WriteLn('PASS: GDI pixels survive JPEG encoding and decoding');
  finally
    Stream.Free;
    Decoded.Free;
    Jpg.Free;
    Bmp.Free;
  end;
  except
    on E: Exception do begin
      WriteLn('FAIL: ', E.Message);
      Halt(1);
    end;
  end;
end.
