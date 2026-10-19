#include <llvm-c/Core.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>
#include <llvm/Support/TargetSelect.h>

int main() {
    static_assert(sizeof(void *) == 4, "SDK smoke must be an actual 32-bit host");
    llvm::InitializeAllTargetInfos();
    llvm::InitializeAllTargets();
    llvm::InitializeAllTargetMCs();
    LLVMContextRef context = LLVMContextCreate();
    LLVMModuleRef cModule = LLVMModuleCreateWithNameInContext("c-api", context);
    LLVMDisposeModule(cModule);
    LLVMContextDispose(context);
    llvm::LLVMContext cppContext;
    llvm::Module cppModule("cpp-api", cppContext);
    return cppModule.getName() == "cpp-api" ? 0 : 1;
}
