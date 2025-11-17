#ifndef MEMORY_PASS_H
#define MEMORY_PASS_H

#include "mlir/Pass/Pass.h"

namespace memory {

/**
 * 创建 Memory 到 MemRef 的转换 Pass
 */
std::unique_ptr<mlir::Pass> createMemoryToMemRefPass();

} // namespace memory

#endif