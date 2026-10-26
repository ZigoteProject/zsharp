// The part of libclang's C API this package uses, as LLVM's clang-c headers declare it (Apache-2.0
// WITH LLVM-exception; the C API is stable). The functions are libclang's, opened when first
// called (shim.c), so a program using them starts where libclang isn't installed.
typedef void *CXIndex;
typedef struct CXTranslationUnitImpl *CXTranslationUnit;
typedef void *CXFile;
typedef void *CXDiagnostic;

typedef struct {
  const void *data;
  unsigned private_flags;
} CXString;

typedef struct {
  const void *ptr_data[2];
  unsigned int_data;
} CXSourceLocation;

typedef struct {
  const void *ptr_data[2];
  unsigned begin_int_data;
  unsigned end_int_data;
} CXSourceRange;

// the cursor kinds this package's users look for
enum CXCursorKind {
  CXCursor_StructDecl = 2,
  CXCursor_UnionDecl = 3,
  CXCursor_EnumDecl = 5,
  CXCursor_FieldDecl = 6,
  CXCursor_EnumConstantDecl = 7,
  CXCursor_FunctionDecl = 8,
  CXCursor_VarDecl = 9,
  CXCursor_ParmDecl = 10,
  CXCursor_TypedefDecl = 20,
  CXCursor_MacroDefinition = 501
};

typedef struct {
  enum CXCursorKind kind;
  int xdata;
  const void *data[3];
} CXCursor;

typedef struct {
  int kind;
  void *data[2];
} CXType;

typedef struct {
  unsigned int_data[4];
  void *ptr_data;
} CXToken;

enum CXChildVisitResult { CXChildVisit_Break, CXChildVisit_Continue, CXChildVisit_Recurse };

enum CX_StorageClass {
  CX_SC_Invalid,
  CX_SC_None,
  CX_SC_Extern,
  CX_SC_Static,
  CX_SC_PrivateExtern,
  CX_SC_OpenCLWorkGroupLocal,
  CX_SC_Auto,
  CX_SC_Register
};

enum CXDiagnosticSeverity {
  CXDiagnostic_Ignored = 0,
  CXDiagnostic_Note = 1,
  CXDiagnostic_Warning = 2,
  CXDiagnostic_Error = 3,
  CXDiagnostic_Fatal = 4
};

enum CXDiagnosticDisplayOptions {
  CXDiagnostic_DisplaySourceLocation = 0x01,
  CXDiagnostic_DisplayColumn = 0x02,
  CXDiagnostic_DisplaySourceRanges = 0x04,
  CXDiagnostic_DisplayOption = 0x08
};

enum CXTranslationUnit_Flags {
  CXTranslationUnit_None = 0x0,
  CXTranslationUnit_DetailedPreprocessingRecord = 0x01,
  CXTranslationUnit_SkipFunctionBodies = 0x40
};

CXIndex clang_createIndex(int excludeDeclarationsFromPCH, int displayDiagnostics);
void clang_disposeIndex(CXIndex index);
void clang_disposeTranslationUnit(CXTranslationUnit);
void clang_disposeString(CXString string);

CXCursor clang_getTranslationUnitCursor(CXTranslationUnit);
enum CXCursorKind clang_getCursorKind(CXCursor);
CXString clang_getCursorSpelling(CXCursor);
CXSourceLocation clang_getCursorLocation(CXCursor);
CXSourceRange clang_getCursorExtent(CXCursor);
CXType clang_getCursorType(CXCursor C);
CXType clang_getTypedefDeclUnderlyingType(CXCursor C);
long long clang_getEnumConstantDeclValue(CXCursor C);
int clang_Cursor_getNumArguments(CXCursor C);
CXCursor clang_Cursor_getArgument(CXCursor C, unsigned i);
enum CX_StorageClass clang_Cursor_getStorageClass(CXCursor);
unsigned clang_Cursor_isMacroFunctionLike(CXCursor C);
unsigned clang_Cursor_isBitField(CXCursor C);

CXString clang_getTypeSpelling(CXType CT);
CXType clang_getResultType(CXType T);
unsigned clang_isFunctionTypeVariadic(CXType T);

int clang_Location_isFromMainFile(CXSourceLocation location);
CXSourceLocation clang_getRangeStart(CXSourceRange range);
CXSourceLocation clang_getRangeEnd(CXSourceRange range);
void clang_getExpansionLocation(CXSourceLocation location, CXFile *file, unsigned *line, unsigned *column,
                                unsigned *offset);
CXString clang_getFileName(CXFile SFile);

void clang_tokenize(CXTranslationUnit TU, CXSourceRange Range, CXToken **Tokens, unsigned *NumTokens);
CXString clang_getTokenSpelling(CXTranslationUnit, CXToken);
CXSourceRange clang_getTokenExtent(CXTranslationUnit, CXToken);
void clang_disposeTokens(CXTranslationUnit TU, CXToken *Tokens, unsigned NumTokens);

unsigned clang_getNumDiagnostics(CXTranslationUnit Unit);
CXDiagnostic clang_getDiagnostic(CXTranslationUnit Unit, unsigned Index);
enum CXDiagnosticSeverity clang_getDiagnosticSeverity(CXDiagnostic);
CXString clang_formatDiagnostic(CXDiagnostic Diagnostic, unsigned Options);
void clang_disposeDiagnostic(CXDiagnostic Diagnostic);
