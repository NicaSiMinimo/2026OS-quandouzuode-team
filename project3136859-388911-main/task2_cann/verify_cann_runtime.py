import argparse
import sys


def check_ret(name, ret):
    if ret != 0:
        raise RuntimeError(f"{name} failed, ret={ret}")


def main():
    parser = argparse.ArgumentParser(description="Verify CANN pyACL runtime on Ascend NPU.")
    parser.add_argument("--device-id", type=int, default=0)
    args = parser.parse_args()

    try:
        import acl
    except Exception as exc:
        print(f"import acl failed: {exc}", file=sys.stderr)
        print("Check ASCEND_TOOLKIT_HOME, PYTHONPATH and LD_LIBRARY_PATH.", file=sys.stderr)
        return 2

    ret = acl.init()
    check_ret("acl.init", ret)

    try:
        device_count, ret = acl.rt.get_device_count()
        check_ret("acl.rt.get_device_count", ret)
        print(f"device_count={device_count}")
        if device_count <= args.device_id:
            raise RuntimeError(f"device {args.device_id} is unavailable")

        ret = acl.rt.set_device(args.device_id)
        check_ret("acl.rt.set_device", ret)

        context, ret = acl.rt.create_context(args.device_id)
        check_ret("acl.rt.create_context", ret)

        run_mode, ret = acl.rt.get_run_mode()
        check_ret("acl.rt.get_run_mode", ret)
        print(f"run_mode={run_mode}")

        mem_info = None
        try:
            free_mem, total_mem, ret = acl.rt.get_mem_info(0)
            if ret == 0:
                mem_info = (free_mem, total_mem)
        except Exception:
            mem_info = None
        if mem_info is not None:
            print(f"device_memory_free={mem_info[0]} device_memory_total={mem_info[1]}")

        ret = acl.rt.destroy_context(context)
        check_ret("acl.rt.destroy_context", ret)
        ret = acl.rt.reset_device(args.device_id)
        check_ret("acl.rt.reset_device", ret)
    finally:
        ret = acl.finalize()
        check_ret("acl.finalize", ret)

    print("CANN runtime verification passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
