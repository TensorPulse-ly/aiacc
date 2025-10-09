#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <dlfcn.h>
#include "svdpi.h"

#ifdef __cplusplus
extern "C" {
#endif

/* VCS error reporting routine */
extern void vcsMsgReport1(const char *, const char *, int, void *, void*, const char *);

#ifndef _VC_TYPES_
#define _VC_TYPES_
/* common definitions shared with DirectC.h */

typedef unsigned int U;
typedef unsigned char UB;
typedef unsigned char scalar;
typedef struct { U c; U d;} vec32;

#define scalar_0 0
#define scalar_1 1
#define scalar_z 2
#define scalar_x 3

extern long long int ConvUP2LLI(U* a);
extern void ConvLLI2UP(long long int a1, U* a2);
extern long long int GetLLIresult();
extern void StoreLLIresult(const unsigned int* data);
typedef struct VeriC_Descriptor *vc_handle;

#ifndef SV_3_COMPATIBILITY
#define SV_STRING const char*
#else
#define SV_STRING char*
#endif

#endif /* _VC_TYPES_ */

#ifndef __VCS_IMPORT_DPI_STUB_fp32_add_8_softfloat
#define __VCS_IMPORT_DPI_STUB_fp32_add_8_softfloat
__attribute__((weak)) unsigned int fp32_add_8_softfloat(/* INPUT */unsigned int A_1, /* INPUT */unsigned int A_2, /* INPUT */unsigned int A_3, /* INPUT */unsigned int A_4, /* INPUT */unsigned int A_5, /* INPUT */unsigned int A_6, /* INPUT */unsigned int A_7, /* INPUT */unsigned int A_8)
{
    static int _vcs_dpi_stub_initialized_ = 0;
    static unsigned int (*_vcs_dpi_fp_)(/* INPUT */unsigned int A_1, /* INPUT */unsigned int A_2, /* INPUT */unsigned int A_3, /* INPUT */unsigned int A_4, /* INPUT */unsigned int A_5, /* INPUT */unsigned int A_6, /* INPUT */unsigned int A_7, /* INPUT */unsigned int A_8) = NULL;
    if (!_vcs_dpi_stub_initialized_) {
        _vcs_dpi_fp_ = (unsigned int (*)(unsigned int A_1, unsigned int A_2, unsigned int A_3, unsigned int A_4, unsigned int A_5, unsigned int A_6, unsigned int A_7, unsigned int A_8)) dlsym(RTLD_NEXT, "fp32_add_8_softfloat");
        _vcs_dpi_stub_initialized_ = 1;
    }
    if (_vcs_dpi_fp_) {
        return _vcs_dpi_fp_(A_1, A_2, A_3, A_4, A_5, A_6, A_7, A_8);
    } else {
        const char *fileName;
        int lineNumber;
        svGetCallerInfo(&fileName, &lineNumber);
        vcsMsgReport1("DPI-DIFNF", fileName, lineNumber, 0, 0, "fp32_add_8_softfloat");
        return 0;
    }
}
#endif /* __VCS_IMPORT_DPI_STUB_fp32_add_8_softfloat */

#ifndef __VCS_IMPORT_DPI_STUB_set_softfloat_rounding_mode
#define __VCS_IMPORT_DPI_STUB_set_softfloat_rounding_mode
__attribute__((weak)) void set_softfloat_rounding_mode(/* INPUT */unsigned int A_1)
{
    static int _vcs_dpi_stub_initialized_ = 0;
    static void (*_vcs_dpi_fp_)(/* INPUT */unsigned int A_1) = NULL;
    if (!_vcs_dpi_stub_initialized_) {
        _vcs_dpi_fp_ = (void (*)(unsigned int A_1)) dlsym(RTLD_NEXT, "set_softfloat_rounding_mode");
        _vcs_dpi_stub_initialized_ = 1;
    }
    if (_vcs_dpi_fp_) {
        _vcs_dpi_fp_(A_1);
    } else {
        const char *fileName;
        int lineNumber;
        svGetCallerInfo(&fileName, &lineNumber);
        vcsMsgReport1("DPI-DIFNF", fileName, lineNumber, 0, 0, "set_softfloat_rounding_mode");
    }
}
#endif /* __VCS_IMPORT_DPI_STUB_set_softfloat_rounding_mode */

#ifndef __VCS_IMPORT_DPI_STUB_clear_softfloat_flags
#define __VCS_IMPORT_DPI_STUB_clear_softfloat_flags
__attribute__((weak)) void clear_softfloat_flags()
{
    static int _vcs_dpi_stub_initialized_ = 0;
    static void (*_vcs_dpi_fp_)() = NULL;
    if (!_vcs_dpi_stub_initialized_) {
        _vcs_dpi_fp_ = (void (*)()) dlsym(RTLD_NEXT, "clear_softfloat_flags");
        _vcs_dpi_stub_initialized_ = 1;
    }
    if (_vcs_dpi_fp_) {
        _vcs_dpi_fp_();
    } else {
        const char *fileName;
        int lineNumber;
        svGetCallerInfo(&fileName, &lineNumber);
        vcsMsgReport1("DPI-DIFNF", fileName, lineNumber, 0, 0, "clear_softfloat_flags");
    }
}
#endif /* __VCS_IMPORT_DPI_STUB_clear_softfloat_flags */

#ifndef __VCS_IMPORT_DPI_STUB_get_softfloat_flags
#define __VCS_IMPORT_DPI_STUB_get_softfloat_flags
__attribute__((weak)) unsigned int get_softfloat_flags()
{
    static int _vcs_dpi_stub_initialized_ = 0;
    static unsigned int (*_vcs_dpi_fp_)() = NULL;
    if (!_vcs_dpi_stub_initialized_) {
        _vcs_dpi_fp_ = (unsigned int (*)()) dlsym(RTLD_NEXT, "get_softfloat_flags");
        _vcs_dpi_stub_initialized_ = 1;
    }
    if (_vcs_dpi_fp_) {
        return _vcs_dpi_fp_();
    } else {
        const char *fileName;
        int lineNumber;
        svGetCallerInfo(&fileName, &lineNumber);
        vcsMsgReport1("DPI-DIFNF", fileName, lineNumber, 0, 0, "get_softfloat_flags");
        return 0;
    }
}
#endif /* __VCS_IMPORT_DPI_STUB_get_softfloat_flags */


#ifdef __cplusplus
}
#endif

