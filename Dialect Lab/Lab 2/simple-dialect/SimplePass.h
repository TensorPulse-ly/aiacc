#ifndef SIMPLE_PASS_H
#define SIMPLE_PASS_H

#include "mlir/Pass/Pass.h"

namespace simple {

std::unique_ptr<mlir::Pass> createSimpleToArithPass();

} // namespace simple

#endif
