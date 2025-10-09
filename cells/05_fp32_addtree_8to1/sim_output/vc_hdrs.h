#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <dlfcn.h>
#include "svdpi.h"

#ifdef __cplusplus
extern "C" {
#endif

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


 extern unsigned int fp32_add_8_softfloat(/* INPUT */unsigned int input0, /* INPUT */unsigned int input1, /* INPUT */unsigned int input2, /* INPUT */unsigned int input3, /* INPUT */unsigned int input4, /* INPUT */unsigned int input5, /* INPUT */unsigned int input6, /* INPUT */unsigned int input7);

 extern void set_softfloat_rounding_mode(/* INPUT */unsigned int mode);

 extern void clear_softfloat_flags();

 extern unsigned int get_softfloat_flags();

#ifdef __cplusplus
}
#endif

