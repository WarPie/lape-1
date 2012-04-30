{
	Author: Niels A.D
	Project: Lape (http://code.google.com/p/la-pe/)
	License: GNU Lesser GPL (http://www.gnu.org/licenses/lgpl.html)

	Foreign function interface extension with help of libffi.
}
unit lpffi;

{$I lape.inc}

interface

uses
  Classes, SysUtils, ffi,
  lptypes, lpvartypes, lpvartypes_array, lpvartypes_record, lpcompiler;

type
  TFFITypeManager = class;
  TFFITypeManager = class(TLapeBaseClass)
  private
    PElems: array of PFFIType;
    Prepared: Boolean;
    procedure TryAlter;
  protected
    FTyp: TFFIType;
    FElems: array of record
      Typ: TFFITypeManager;
      DoFree: Boolean;
    end;

    function getTyp: TFFIType;
    procedure setTyp(ATyp: TFFIType);
    function getPTyp: PFFIType;
    procedure PrepareType;
  public
    constructor Create(FFIType: TFFIType); reintroduce;
    destructor Destroy; override;

    procedure addElem(Elem: TFFITypeManager; DoManage: Boolean = True); overload;
    procedure addElem(Elem: TFFIType); overload;

    property Typ: TFFIType read getTyp write setTyp;
    property PTyp: PFFIType read getPTyp;
  end;

  TArrayOfPointer = array of Pointer;
  TFFICifManager = class(TLapeBaseClass)
  private
    PArgs: array of PFFIType;
    Prepared: Boolean;
    procedure TryAlter;
  protected
    FCif: TFFICif;
    FABI: TFFIABI;
    FArgs: array of record
      Typ: TFFITypeManager;
      DoFree: Boolean;
      TakePointer: Boolean;
    end;
    FRes: TFFITypeManager;

    procedure setABI(AABI: TFFIABI);
    procedure setRes(ARes: TFFITypeManager);
    function getCif: TFFICif;
    function getPCif: PFFICif;
    procedure PrepareCif;
  public
    ManageResType: Boolean;

    constructor Create(AABI: TFFIABI = FFI_DEFAULT_ABI); reintroduce; overload;
    constructor Create(ArgTypes: array of TFFITypeManager; ResType: TFFITypeManager = nil; AABI: TFFIABI = FFI_DEFAULT_ABI); overload;
    constructor Create(ArgTypes: array of TFFIType; ResType: TFFIType = nil; AABI: TFFIABI = FFI_DEFAULT_ABI); overload;
    destructor Destroy; override;

    procedure addArg(Arg: TFFITypeManager; DoManage: Boolean = True; TakePtr: Boolean = False); overload;
    procedure addArg(Arg: TFFIType; TakePtr: Boolean = False); overload;
    function TakePointers(Args: PPointerArray; TakeAddr: Boolean = True): TArrayOfPointer;

    procedure Call(Func, Res: Pointer; Args: PPointerArray; ATakePointers: Boolean = True); overload;
    procedure Call(Func, Res: Pointer); overload;
    procedure Call(Func, Res: Pointer; Args: array of Pointer; ATakePointers: Boolean = True); overload;
    procedure Call(Func: Pointer; Args: array of Pointer; ATakePointers: Boolean = True); overload;

    property ABI: TFFIABI read FABI write setABI;
    property Res: TFFITypeManager read FRes write setRes;
    property Cif: TFFICif read getCif;
    property PCif: PFFICif read getPCif;
  end;

  generic TFFIClosureManager<TUserData> = class(TLapeBaseClass)
  public type
    TFreeUserData = procedure(AData: TUserData);
  var private
    Prepared: Boolean;
    procedure TryAlter;
  protected
    FClosure: PFFIClosure;
    FCif: TFFICifManager;
    FCallback: TClosureBindingFunction;
    FFunc: Pointer;

    function getClosure: TFFIClosure;
    function getPClosure: PFFIClosure;
    procedure setCif(ACif: TFFICifManager);
    procedure setCallback(AFunc: TClosureBindingFunction);
    function getFunc: Pointer;
    procedure PrepareClosure;
  public
    UserData: TUserData;
    ManageCif: Boolean;
    FreeData: TFreeUserData;

    constructor Create(ACif: TFFICifManager = nil; ACallback: TClosureBindingFunction = nil); reintroduce;
    destructor Destroy; override;

    property Closure: TFFIClosure read getClosure;
    property PClosure: PFFIClosure read getPClosure;
    property Cif: TFFICifManager read FCif write setCif;
    property Callback: TClosureBindingFunction read FCallback write setCallback;
    property Func: Pointer read getFunc;
  end;

const
  lpeAlterPrepared = 'Cannot alter an already prepared object';
  lpeCannotPrepare = 'Cannot prepare object';

function LapeTypeToFFIType(VarType: TLapeType): TFFITypeManager;
function LapeFFIPointerParam(ParType: ELapeParameterType): Boolean;
function LapeParamToFFIType(Param: TLapeParameter): TFFITypeManager;
function LapeHeaderToFFICif(Header: TLapeType_Method; ABI: TFFIABI = FFI_DEFAULT_ABI): TFFICifManager; overload;
function LapeHeaderToFFICif(Compiler: TLapeCompiler; Header: lpString; ABI: TFFIABI = FFI_DEFAULT_ABI): TFFICifManager; overload;

type
  TImportClosureData = packed record
    NativeFunc: Pointer;
    NativeCif: TFFICifManager;
  end;
  TImportClosure = specialize TFFIClosureManager<TImportClosureData>;

  TExportClosureData = record
    LapeFunc: TCodePos;
  end;
  TExportClosure = specialize TFFIClosureManager<TExportClosureData>;

function LapeImportWrapper(Func: Pointer;  Header: TLapeType_Method; ABI: TFFIABI = FFI_DEFAULT_ABI): TImportClosure;
function LapeExportWrapper(Func: TCodePos; Header: TLapeType_Method; ABI: TFFIABI = FFI_DEFAULT_ABI): TExportClosure;

implementation

uses
  lpexceptions, lpparser;

procedure TFFITypeManager.TryAlter;
begin
  if Prepared then
    LapeException(lpeAlterPrepared);
end;

function TFFITypeManager.getTyp: TFFIType;
begin
  PrepareType();
  Result := FTyp;
end;

procedure TFFITypeManager.setTyp(ATyp: TFFIType);
begin
  TryAlter();
  FTyp := ATyp;
end;

function TFFITypeManager.getPTyp: PFFIType;
begin
  PrepareType();
  Result := @FTyp;
end;

procedure TFFITypeManager.PrepareType;
var
  i, l: Integer;
begin
  l := Length(FElems);
  if (l <= 1) or Prepared then
    Exit;

  FillChar(FTyp, SizeOf(TFFIType), 0);

  SetLength(PElems, l + 1);
  for i := 0 to l - 1 do
    PElems[i] := FElems[i].Typ.PTyp;
  PElems[l] := nil;

  FTyp._type := Ord(FFI_CTYPE_STRUCT);
  FTyp.elements := @PElems[0];
  Prepared := True;
end;

constructor TFFITypeManager.Create(FFIType: TFFIType);
begin
  inherited Create();

  PElems := nil;
  Prepared := False;

  FTyp := FFIType;
  FElems := nil;
end;

destructor TFFITypeManager.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FElems) do
    if FElems[i].DoFree then
      FElems[i].Typ.Free();
  inherited;
end;

procedure TFFITypeManager.addElem(Elem: TFFITypeManager; DoManage: Boolean = True);
begin
  Assert(Elem <> nil);
  TryAlter();

  SetLength(FElems, Length(FElems) + 1);
  with FElems[High(FElems)] do
  begin
    Typ := Elem;
    DoFree := DoManage;
  end;
end;

procedure TFFITypeManager.addElem(Elem: TFFIType);
begin
  addElem(TFFITypeManager.Create(Elem), True);
end;

procedure TFFICifManager.TryAlter;
begin
  if Prepared then
    LapeException(lpeAlterPrepared);
end;

procedure TFFICifManager.setABI(AABI: TFFIABI);
begin
  TryAlter();
  FABI := AABI;
end;

procedure TFFICifManager.setRes(ARes: TFFITypeManager);
begin
  TryAlter();
  if (FRes <> nil) and (FRes <> ARes) and ManageResType then
    FRes.Free();
  FRes := ARes;
end;

function TFFICifManager.getCif: TFFICif;
begin
  PrepareCif();
  Result := FCif;
end;

function TFFICifManager.getPCif: PFFICif;
begin
  PrepareCif();
  Result := @FCif;
end;

procedure TFFICifManager.PrepareCif;
var
  i: Integer;
  r, a: Pointer;
begin
  if Prepared then
    Exit;

  SetLength(PArgs, Length(FArgs));
  for i := 0 to High(FArgs) do
    PArgs[i] := FArgs[i].Typ.PTyp;

  if (FRes <> nil) then
    r := FRes.PTyp
  else
    r := nil;

  if (Length(FArgs) > 0) then
    a := @PArgs[0]
  else
    a := nil;

  if (ffi_prep_cif(FCif, FABI, Length(FArgs), r, a) <> FFI_OK) then
    LapeException(lpeCannotPrepare);
  Prepared := True;
end;

constructor TFFICifManager.Create(AABI: TFFIABI = FFI_DEFAULT_ABI);
begin
  inherited Create();
  FillChar(FCif, SizeOf(TFFICif), 0);

  PArgs := nil;
  Prepared := False;
  ManageResType := True;

  FABI := AABI;
  FArgs := nil;
  FRes := nil;
end;

constructor TFFICifManager.Create(ArgTypes: array of TFFITypeManager; ResType: TFFITypeManager = nil; AABI: TFFIABI = FFI_DEFAULT_ABI);
var
  i: Integer;
begin
  Create(AABI);
  Res := ResType;
  for i := 0 to High(ArgTypes) do
    addArg(ArgTypes[i]);
end;

constructor TFFICifManager.Create(ArgTypes: array of TFFIType; ResType: TFFIType = nil; AABI: TFFIABI = FFI_DEFAULT_ABI);
var
  i: Integer;
begin
  Create(AABI);
  Res := TFFITypeManager.Create(ResType);
  for i := 0 to High(ArgTypes) do
    addArg(ArgTypes[i]);
end;

destructor TFFICifManager.Destroy;
var
  i: Integer;
begin
  if (FRes <> nil) and ManageResType then
    FRes.Free();
  for i := 0 to High(FArgs) do
    if FArgs[i].DoFree then
      FArgs[i].Typ.Free();
  inherited;
end;

procedure TFFICifManager.addArg(Arg: TFFITypeManager; DoManage: Boolean = True; TakePtr: Boolean = False);
begin
  Assert(Arg <> nil);
  TryAlter();

  SetLength(FArgs, Length(FArgs) + 1);
  with FArgs[High(FArgs)] do
  begin
    Typ := Arg;
    DoFree := DoManage;
    TakePointer := TakePtr;
  end;
end;

procedure TFFICifManager.addArg(Arg: TFFIType; TakePtr: Boolean = False);
begin
  addArg(TFFITypeManager.Create(Arg), True, TakePtr);
end;

function TFFICifManager.TakePointers(Args: PPointerArray; TakeAddr: Boolean = True): TArrayOfPointer;
var
  i: Integer;
begin
  Result := nil;
  if (Args = nil) or (Length(FArgs) <= 0) then
    Exit;

  SetLength(Result, Length(FArgs));
  if TakeAddr then
    for i := 0 to High(Result) do
      if FArgs[i].TakePointer then
        Result[i] := @Args^[i]
      else
        Result[i] := Args^[i]
  else
    for i := 0 to High(Result) do
      if FArgs[i].TakePointer then
        Result[i] := PPointer(Args^[i])^
      else
        Result[i] := Args^[i];
end;

procedure TFFICifManager.Call(Func, Res: Pointer; Args: PPointerArray; ATakePointers: Boolean = True);
var
  p: TArrayOfPointer;
begin
  PrepareCif();
  if ATakePointers then
  begin
    p := TakePointers(Args);
    if (Length(p) > 0) then
      Args := @p[0];
  end;

  ffi_call(FCif, Func, Res, Args);
end;

procedure TFFICifManager.Call(Func, Res: Pointer);
begin
  Call(Func, Res, PPointerArray(nil), False);
end;

procedure TFFICifManager.Call(Func, Res: Pointer; Args: array of Pointer; ATakePointers: Boolean = True);
begin
  if (Length(Args) > 0) then
    Call(Func, Res, PPointerArray(@Args[0]), ATakePointers)
  else
    Call(Func, Res);
end;

procedure TFFICifManager.Call(Func: Pointer; Args: array of Pointer; ATakePointers: Boolean = True);
begin
  Call(Func, nil, Args, ATakePointers);
end;

procedure TFFIClosureManager.TryAlter;
begin
  if Prepared then
    LapeException(lpeAlterPrepared);
end;

function TFFIClosureManager.getClosure: TFFIClosure;
begin
  PrepareClosure();
  Result := FClosure^;
end;

function TFFIClosureManager.getPClosure: PFFIClosure;
begin
  PrepareClosure();
  Result := FClosure;
end;

procedure TFFIClosureManager.setCif(ACif: TFFICifManager);
begin
  TryAlter();
  if (FCif <> nil) and (FCif <> ACif) and ManageCif then
    FCif.Free();
  FCif := ACif;
end;

procedure TFFIClosureManager.setCallback(AFunc: TClosureBindingFunction);
begin
  TryAlter();
  FCallback := AFunc;
end;

function TFFIClosureManager.getFunc: Pointer;
begin
  PrepareClosure();
  Result := FFunc;
end;

procedure TFFIClosureManager.PrepareClosure;
begin
  if Prepared then
    Exit;

  if (FCif = nil) or
     (FCallback = nil) or
     (ffi_prep_closure_loc(FClosure^, FCif.PCif^, FCallback, @UserData, FFunc) <> FFI_OK)
  then
    LapeException(lpeCannotPrepare);

  Prepared := True;
end;

constructor TFFIClosureManager.Create(ACif: TFFICifManager = nil; ACallback: TClosureBindingFunction = nil);
begin
  inherited Create();

  Prepared := False;
  ManageCif := True;
  FreeData := nil;

  FClosure := ffi_closure_alloc(SizeOf(TFFIClosure), FFunc);
  FCif := ACif;
  FCallback := ACallback;
end;

destructor TFFIClosureManager.Destroy;
begin
  if (FreeData <> nil) then
    FreeData(UserData);
  if (FCif <> nil) and ManageCif then
    FCif.Free();
  if (FClosure <> nil) then
    ffi_closure_free(FClosure);
  inherited;
end;

function LapeTypeToFFIType(VarType: TLapeType): TFFITypeManager;

  function ConvertBaseIntType(BaseType: ELapeBaseType): TFFIType;
  begin
    case BaseType of
      ltUInt8:  Result := ffi_type_uint8;
      ltInt8:   Result := ffi_type_sint8;
      ltUInt16: Result := ffi_type_uint16;
      ltInt16:  Result := ffi_type_sint16;
      ltUInt32: Result := ffi_type_uint32;
      ltInt32:  Result := ffi_type_sint32;
      ltUInt64: Result := ffi_type_uint64;
      ltInt64:  Result := ffi_type_sint64;
      else      Result := ffi_type_void;
    end;
  end;

  procedure FFIArray(Size: Integer; FFIType: TFFITypeManager);
  var
    i: Integer;
  begin
    for i := 0 to Size - 1 do
      Result.addElem(FFIType, i = 0);
  end;

  procedure FFIStaticArray(VarType: TLapeType_StaticArray);
  begin
    if (VarType = nil) or (VarType.Range.Lo > VarType.Range.Hi) then
      LapeException(lpeInvalidCast);
    FFIArray(VarType.Range.Hi - VarType.Range.Lo + 1, LapeTypeToFFIType(VarType.PType));
  end;

  procedure FFIRecord(VarType: TLapeType_Record);
  var
    i: Integer;
  begin
    if (VarType = nil) or (VarType.FieldMap.Count < 1) then
      LapeException(lpeInvalidCast);

    for i := 0 to VarType.FieldMap.Count - 1 do
      Result.addElem(LapeTypeToFFIType(VarType.FieldMap.ItemsI[i].FieldType));
  end;

  procedure FFIUnion(VarType: TLapeType_Union);
  var
    i, m: Integer;
  begin
    if (VarType = nil) or (VarType.FieldMap.Count < 1) then
      LapeException(lpeInvalidCast);

    with VarType.FieldMap do
    begin
      m := 0;
      for i := 1 to Count - 1 do
        if (ItemsI[i].FieldType.Size > ItemsI[m].FieldType.Size) then
          m := i;

      Result := LapeTypeToFFIType(ItemsI[m].FieldType);
    end;
  end;

begin
  Result := TFFITypeManager.Create(ffi_type_void);
  if (VarType = nil) or (VarType.Size <= 0) then
    Exit;

  try
    if (VarType.BaseIntType <> ltUnknown) then
      Result.Typ := ConvertBaseIntType(VarType.BaseIntType)
    else if (VarType.BaseType in LapePointerTypes) then
      Result.Typ := ffi_type_pointer
    else
      case VarType.BaseType of
        ltSingle:      Result.Typ := ffi_type_float;
        ltDouble:      Result.Typ := ffi_type_double;
        ltCurrency:    Result.Typ := ffi_type_uint64;
        ltExtended:    Result.Typ := ffi_type_longdouble;
        ltSmallEnum,
        ltLargeEnum:   Result.Typ := ConvertBaseIntType(DetermineIntType(VarType.Size, False));
        ltSmallSet:    Result.Typ := ffi_type_uint32;
        ltShortString,
        ltVariant,
        ltLargeSet:    FFIArray(VarType.Size, TFFITypeManager.Create(ffi_type_uint8));
        ltStaticArray: FFIStaticArray(VarType as TLapeType_StaticArray);
        ltRecord:      FFIRecord(VarType as TLapeType_Record);
        ltUnion:       FFIUnion(VarType as TLapeType_Union);
      end;
  except
    Result.Free();
  end;
end;

function LapeFFIPointerParam(ParType: ELapeParameterType): Boolean;
begin
  Result := ParType in [lptVar, lptOut];
end;

function LapeParamToFFIType(Param: TLapeParameter): TFFITypeManager;
begin
  if LapeFFIPointerParam(Param.ParType) or (Param.VarType = nil) then
    Result := TFFITypeManager.Create(ffi_type_pointer)
  else
    Result := LapeTypeToFFIType(Param.VarType);
end;

function LapeHeaderToFFICif(Header: TLapeType_Method; ABI: TFFIABI = FFI_DEFAULT_ABI): TFFICifManager;
var
  i: Integer;
begin
  if (Header = nil) then
    Exit(nil);

  Result := TFFICifManager.Create(ABI);
  if (Header.Res <> nil) then
    Result.Res := LapeTypeToFFIType(Header.Res);

  try
    if MethodOfObject(Header) then
      Result.addArg(ffi_type_pointer);
    for i := 0 to Header.Params.Count - 1 do
      Result.addArg(LapeParamToFFIType(Header.Params[i]), True, LapeFFIPointerParam(Header.Params[i].ParType));
  except
    Result.Free();
  end;
end;

type
  __LapeCompiler = class(TLapeCompiler);
function LapeHeaderToFFICif(Compiler: TLapeCompiler; Header: lpString; ABI: TFFIABI = FFI_DEFAULT_ABI): TFFICifManager;
var
  c: __LapeCompiler absolute Compiler;
  s: lpString;
  Method: TLapeType_Method;
  OldState: Pointer;
begin
  if (c = nil) or (Header = '') then
    Exit(nil);

  OldState := c.getTempTokenizerState(Header + ';', 'ffi');
  try
    c.Expect([tk_kw_Function, tk_kw_Procedure]);
    Method := c.ParseMethodHeader(s, False);

    if (Method <> nil) then
      Result := LapeHeaderToFFICif(Method, ABI)
    else
      LapeException(lpeInvalidEvaluation);
  finally
    c.resetTokenizerState(OldState);
  end;
end;

function LapeImportWrapper(Func: Pointer; Header: TLapeType_Method; ABI: TFFIABI = FFI_DEFAULT_ABI): TImportClosure;
begin
end;

function LapeExportWrapper(Func: TCodePos; Header: TLapeType_Method; ABI: TFFIABI = FFI_DEFAULT_ABI): TExportClosure;
begin
end;

end.
