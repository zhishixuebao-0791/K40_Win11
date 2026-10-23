// K40（SM8250）PEP0 桩驱动
// 背景：qcpep8250/qcpep8280 在 SM8250 上都会访问不存在的硬件而卡死（突破 11、12），
//       而 qcsmmu8280 / qcsubsys8280 只需要 PEP 提供两样东西（notes/pep-stub-interface-analysis-20261023.md）：
//   1. 设备接口 {55beca03-ba2c-4fbc-9efc-ee8eca56f0c7} 存在，且能打开（IRP_MJ_CREATE 成功）；
//   2. QueryInterface {a0e1dd36-dfb9-4c0e-bbaa-78f0746be181}，Size 0x28、Version 1，
//      +0x20 处一个函数：参数为设备 AeoB 电源资源文件的缓冲区，返回 NTSTATUS。
// 本驱动只做这两件事：不访问任何 MMIO，不注册 PoFx PEP 插件。
// {99f8bbdb}（异步回调接口）首测不提供，qcsmmu8280 中对它的使用是可选的。
#include <ntddk.h>
#include <wdf.h>
#include <initguid.h>

// {55beca03-ba2c-4fbc-9efc-ee8eca56f0c7}：PEP 设备接口
DEFINE_GUID(GUID_DEVINTERFACE_QCPEP,
    0x55beca03, 0xba2c, 0x4fbc, 0x9e, 0xfc, 0xee, 0x8e, 0xca, 0x56, 0xf0, 0xc7);
// {a0e1dd36-dfb9-4c0e-bbaa-78f0746be181}：注册设备电源资源（同步）
DEFINE_GUID(GUID_QCPEP_RESOURCE_INTERFACE,
    0xa0e1dd36, 0xdfb9, 0x4c0e, 0xbb, 0xaa, 0x78, 0xf0, 0x74, 0x6b, 0xe1, 0x81);

typedef NTSTATUS (*PFN_PEP_REGISTER_RESOURCES)(_In_opt_ PVOID ResourceBuffer);

typedef struct _QCPEP_RESOURCE_INTERFACE {
    INTERFACE Header;                               // 0x00..0x1f
    PFN_PEP_REGISTER_RESOURCES RegisterResources;   // 0x20
} QCPEP_RESOURCE_INTERFACE;

C_ASSERT(FIELD_OFFSET(QCPEP_RESOURCE_INTERFACE, RegisterResources) == 0x20);
C_ASSERT(sizeof(QCPEP_RESOURCE_INTERFACE) == 0x28);

// kd 不能正确显示 UTF-8 中文，调试输出用 ASCII
#define STUB_PREFIX "pep0stub: "
#define StubLog(...) DbgPrintEx(DPFLTR_IHVDRIVER_ID, DPFLTR_ERROR_LEVEL, STUB_PREFIX __VA_ARGS__)

DRIVER_INITIALIZE DriverEntry;
EVT_WDF_DRIVER_DEVICE_ADD StubEvtDeviceAdd;

static ULONG g_RegisterCount;   // 仅用于调试输出，不要求原子

// 照搬 qcpep8280 的行为：IRQL 高于 PASSIVE 时返回 STATUS_ACCESS_DENIED，否则直接成功。
static NTSTATUS StubRegisterResources(_In_opt_ PVOID ResourceBuffer)
{
    ULONG n = ++g_RegisterCount;
    KIRQL irql = KeGetCurrentIrql();
    if (irql > PASSIVE_LEVEL) {
        StubLog("RegisterResources #%lu: IRQL=%u > PASSIVE, ACCESS_DENIED\n", n, (ULONG)irql);
        return STATUS_ACCESS_DENIED;
    }
    StubLog("RegisterResources #%lu: buffer=%p -> SUCCESS\n", n, ResourceBuffer);
    return STATUS_SUCCESS;
}

NTSTATUS DriverEntry(PDRIVER_OBJECT DriverObject, PUNICODE_STRING RegistryPath)
{
    WDF_DRIVER_CONFIG config;
    NTSTATUS status;

    WDF_DRIVER_CONFIG_INIT(&config, StubEvtDeviceAdd);
    status = WdfDriverCreate(DriverObject, RegistryPath, WDF_NO_OBJECT_ATTRIBUTES, &config, WDF_NO_HANDLE);
    StubLog("DriverEntry status=0x%08x\n", status);
    return status;
}

NTSTATUS StubEvtDeviceAdd(WDFDRIVER Driver, PWDFDEVICE_INIT DeviceInit)
{
    WDFDEVICE device;
    QCPEP_RESOURCE_INTERFACE iface;
    WDF_QUERY_INTERFACE_CONFIG qiConfig;
    NTSTATUS status;

    UNREFERENCED_PARAMETER(Driver);

    status = WdfDeviceCreate(&DeviceInit, WDF_NO_OBJECT_ATTRIBUTES, &device);
    if (!NT_SUCCESS(status)) {
        StubLog("WdfDeviceCreate failed 0x%08x\n", status);
        return status;
    }

    RtlZeroMemory(&iface, sizeof(iface));
    iface.Header.Size = sizeof(iface);
    iface.Header.Version = 1;
    iface.Header.Context = (PVOID)device;
    iface.Header.InterfaceReference = WdfDeviceInterfaceReferenceNoOp;
    iface.Header.InterfaceDereference = WdfDeviceInterfaceDereferenceNoOp;
    iface.RegisterResources = StubRegisterResources;

    // KMDF 会把 iface 拷贝保存，之后收到 IRP_MN_QUERY_INTERFACE 时复制给调用者
    WDF_QUERY_INTERFACE_CONFIG_INIT(&qiConfig, (PINTERFACE)&iface, &GUID_QCPEP_RESOURCE_INTERFACE, NULL);
    status = WdfDeviceAddQueryInterface(device, &qiConfig);
    if (!NT_SUCCESS(status)) {
        StubLog("WdfDeviceAddQueryInterface failed 0x%08x\n", status);
        return status;
    }

    // 设备接口最后创建：KMDF 在设备启动后才启用它，此时 QueryInterface 已就绪。
    status = WdfDeviceCreateDeviceInterface(device, &GUID_DEVINTERFACE_QCPEP, NULL);
    if (!NT_SUCCESS(status)) {
        StubLog("WdfDeviceCreateDeviceInterface failed 0x%08x\n", status);
        return status;
    }

    StubLog("AddDevice done: interface {55beca03} + QueryInterface {a0e1dd36} ready\n");
    return STATUS_SUCCESS;
}
