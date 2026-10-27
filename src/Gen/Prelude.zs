/// The text every module of a program starts with (the F# compiler's Codegen.prelude): the
/// runtime's declarations and the reference counting helpers every program uses, in LLVM IR with
/// the word placeholders (i_W, HDR1, HDR2) Module.resolveWord fills in.

/// The module's start.
let prelude = """; zs_alloc's memory isn't uninitialized: it writes the pool byte of the header word
declare noalias ptr @zs_alloc(i_W) allockind("alloc") allocsize(0) "alloc-family"="zs"
declare void @zs_free(ptr allocptr) allockind("free") "alloc-family"="zs"
declare i_W @zs_allocations()
declare i_W @zs_mallocs()
declare ptr @zs_ptr_alloc(i_W, i_W)
declare void @zs_ptr_free(ptr)
declare i64 @zs_ticks()
declare void @zs_set_args(i32, ptr)
declare void @zs_exit(i_W) noreturn
declare void @llvm.memcpy.p0.p0.i_W(ptr, ptr, i_W, i1)
declare void @llvm.memmove.p0.p0.i_W(ptr, ptr, i_W, i1)
declare zeroext i1 @zs_parse_int(ptr, i64, i1 zeroext, i64, ptr)
declare zeroext i1 @zs_parse_float(ptr, ptr)
declare ptr @zs_format_int(i64, i64, i1 zeroext, ptr)
declare ptr @zs_format_float(double, ptr)
declare void @zs_panic(ptr) noreturn
declare void @zs_panic_c(ptr) noreturn
declare ptr @zs_str_of_lanes(ptr, i_W, i_W)
declare noalias ptr @zs_coro_alloc(i_W)
declare token @llvm.coro.id(i32, ptr, ptr, ptr)
declare i_W @llvm.coro.size.i_W()
declare ptr @llvm.coro.begin(token, ptr)
declare token @llvm.coro.save(ptr)
declare i8 @llvm.coro.suspend(token, i1)
declare ptr @llvm.coro.free(token, ptr)
declare void @llvm.coro.end(ptr, i1, token)
declare void @llvm.coro.resume(ptr)
declare void @llvm.coro.destroy(ptr)
declare zeroext i1 @zs_cpu_supports(ptr)
declare void @zs_loop_spawn(ptr)
@zs_marked = external global i_W
declare i_W @zs_marks()
declare i_W @zs_loop_expect(ptr)
declare void @zs_loop_fulfill(i_W)
declare ptr @zs_par_fork(ptr, ptr, i_W)
declare ptr @zs_par_join(ptr)
declare void @zs_par_free(ptr)
declare i_W @zs_par_workers()
declare void @zs_lock(ptr)
declare void @zs_unlock(ptr)
declare ptr @zs_chan_new(i_W, i_W, ptr)
declare void @zs_chan_send(ptr, ptr)
declare zeroext i1 @zs_chan_recv(ptr, ptr)
declare void @zs_chan_close(ptr)
declare void @zs_chan_free(ptr)
declare ptr @zs_spsc_new(i_W, i_W, ptr)
declare zeroext i1 @zs_spsc_push(ptr, ptr)
declare zeroext i1 @zs_spsc_pop(ptr, ptr)
declare void @zs_spsc_free(ptr)
declare ptr @zs_weak_new(ptr)
declare ptr @zs_weak_target(ptr)
declare void @zs_weak_free(ptr)
declare void @zs_arena_open()
declare void @zs_arena_close()
declare void @zs_reused(ptr)
declare ptr @zs_handle_new(ptr, ptr, i1, ptr)
declare ptr @zs_handle_get(ptr)
declare void @zs_callback_thread(ptr, ptr)
declare void @zs_callback_owner(ptr)
declare void @zs_release(ptr)
declare ptr @zs_str_concat(ptr, ptr)
declare ptr @zs_str_concat_n(ptr, i_W)
declare i_W @zs_str_cmp(ptr, ptr)
declare i_W @zs_str_hash(ptr)
declare ptr @zs_str_of_i64(i64)
declare ptr @zs_str_of_u64(i64)
declare ptr @zs_str_of_f64(double)
declare ptr @zs_str_of_f32(float)
declare ptr @zs_str_of_bool(i1 zeroext)
declare ptr @zs_str_of_char(i32)
declare void @zs_print(ptr)
declare void @zs_println(ptr)
declare ptr @zs_str_from_c(ptr)
declare ptr @zs_str_sub(ptr, i_W, i_W)
declare ptr @zs_str_slice(ptr, i_W, i_W)
declare ptr @zs_str_of_bytes(ptr, i_W)
declare void @zs_slice_fail(i_W, i_W, i_W, i_W) noreturn cold
declare void @zs_fixed_fail(ptr, i_W) noreturn cold
declare zeroext i8 @zs_str_byte(ptr, i_W)
declare ptr @zs_str_of_byte(i8 zeroext)
declare i_W @zs_str_index_of(ptr, ptr, i_W)
declare ptr @zs_str_trim(ptr)
declare ptr @zs_str_upper(ptr)
declare ptr @zs_str_lower(ptr)
declare ptr @zs_str_replace(ptr, ptr, ptr)
declare zeroext i1 @zs_str_is_float(ptr)
declare double @zs_str_to_float(ptr)
declare double @llvm.sqrt.f64(double)
declare float @llvm.sqrt.f32(float)
declare ptr @zs_read_line()
declare i_W @zs_argc()
declare i64 @zs_clock_realtime()
declare i64 @zs_random_seed()
declare i_W @zs_file_open(ptr, i_W)
declare i64 @zs_file_mtime(ptr)
declare i64 @zs_file_size(ptr)
declare void @zs_file_touch(ptr)
declare void @zs_file_copy(ptr, ptr)
declare void @zs_file_move(ptr, ptr)
declare ptr @zs_temp_file(ptr)
declare ptr @zs_temp_dir(ptr)
declare void @zs_dir_delete(ptr)
declare zeroext i1 @zs_is_symlink(ptr)
declare ptr @zs_current_dir()
declare i_W @zs_process_start(ptr, ptr, ptr, i1 zeroext, ptr, i_W, i_W, i_W)
declare i_W @zs_process_pipe(i_W)
declare i_W @zs_process_wait(i_W)
declare i_W @zs_process_kill(i_W)
declare i_W @zs_unix_listen(ptr)
declare i_W @zs_unix_connect(ptr)
declare ptr @zs_arg(i_W)
declare zeroext i1 @zs_env_has(ptr)
declare ptr @zs_env_get(ptr)
declare zeroext i1 @zs_io_ok()
declare ptr @zs_io_error()
declare ptr @zs_file_read(ptr)
declare void @zs_file_write(ptr, ptr)
declare void @zs_file_append(ptr, ptr)
declare zeroext i1 @zs_file_exists(ptr)
declare void @zs_file_delete(ptr)
declare zeroext i1 @zs_dir_exists(ptr)
declare void @zs_dir_create(ptr)
declare ptr @zs_dir_list(ptr)
declare ptr @zs_process_run(ptr, ptr)
declare i_W @zs_process_code()
declare zeroext i1 @zs_eof()
declare void @zs_eprintln(ptr)
declare void @zs_loop_post(ptr)
declare void @zs_loop_wait(i_W, i1 zeroext, ptr)
declare void @zs_loop_unwait(i_W, i1 zeroext)
declare i_W @zs_loop_timer(i_W, ptr)
declare void @zs_loop_untimer(i_W)
declare zeroext i1 @zs_loop_step()
declare i_W @zs_loop_jobs()
declare void @zs_loop_close()
declare zeroext i1 @zs_loop_enter()
declare void @zs_loop_leave()
declare void @zs_loop_blocking(ptr, ptr)
declare void @zs_loop_irq_wait(i_W, ptr)
declare void @zs_loop_irq_unwait(i_W)
declare i_W @zs_signal_new()
declare void @zs_signal_set(i_W)
declare zeroext i1 @zs_signal_take(i_W)
declare void @zs_signal_wait(i_W, ptr)
declare void @zs_signal_unwait(i_W)
declare void @zs_set_clock(i32)
declare i_W @zs_tcp_listen(ptr, i_W)
declare i_W @zs_tcp_accept(i_W)
declare i_W @zs_tcp_connect(ptr, i_W)
declare i_W @zs_socket_error(i_W)
declare i_W @zs_fd_read(i_W, ptr, i_W, i_W, i_W)
declare i_W @zs_fd_write(i_W, ptr, i_W, i_W, i_W)
declare void @zs_fd_close(i_W)
declare ptr @zs_error_text(i_W)

; an object's count is the first 32 bits of its header word. Above 0 it's a thread-local
; object's, 0 a static one's (never freed), and below 0 a shared object's, -n for n references,
; counted atomically (DESIGN §7.1): a program with threads has threadedRc's versions of these
; two, which count it. A count past 2^31 turns negative and stays: the object is never freed.
define private void @zs.dup(ptr %p) alwaysinline {
entry:
  %rc = load i32, ptr %p
  %local = icmp sgt i32 %rc, 0
  br i1 %local, label %inc, label %done
inc:
  %n = add i32 %rc, 1
  store i32 %n, ptr %p
  br label %done
done:
  ret void
}

; an option's empty case when the other one holds a pointer (option<string>): a static object
; (count 0, never freed), compared by its address
@zs.none = private constant { i_W } { i_W 0 }

; every empty array literal ([||]): a static object (count 0, never freed) of length 0, so an
; empty array costs no allocation (and a write to it copies it first, as to any shared array)
@zs.noelems = private constant { i_W, i_W } { i_W 0, i_W 0 }

; true when this was the last reference (the caller frees the object)
define private i1 @zs.release(ptr %p) alwaysinline {
entry:
  %rc = load i32, ptr %p
  %last = icmp eq i32 %rc, 1
  br i1 %last, label %yes, label %no
yes:
  ret i1 true
no:
  %more = icmp sgt i32 %rc, 1
  br i1 %more, label %dec, label %keep
dec:
  %n = sub i32 %rc, 1
  store i32 %n, ptr %p
  br label %keep
keep:
  ret i1 false
}

define private void @zs.drop.str(ptr %p) {
entry:
  %last = call i1 @zs.release(ptr %p)
  br i1 %last, label %free, label %done
free:
  call void @zs_free(ptr %p)
  ret void
done:
  ret void
}

; a dyn Trait value: { count, vtable, the value }; the vtable's first entry frees it
define private void @zs.drop.dyn(ptr %p) {
entry:
  %last = call i1 @zs.release(ptr %p)
  br i1 %last, label %free, label %done
free:
  %vp = getelementptr { i_W, ptr }, ptr %p, i32 0, i32 1
  %vt = load ptr, ptr %vp
  %f = load ptr, ptr %vt
  call void %f(ptr %p)
  ret void
done:
  ret void
}

define private void @zs.drop.clo(ptr %p) {
entry:
  %last = call i1 @zs.release(ptr %p)
  br i1 %last, label %free, label %done
free:
  %ip = getelementptr { i_W, ptr, ptr }, ptr %p, i32 0, i32 2
  %info = load ptr, ptr %ip
  %f = load ptr, ptr %info
  call void %f(ptr %p)
  ret void
done:
  ret void
}

; the event loop's ways with the closures it owns (unit -> unit, runtime/rt.c): call one and give
; up the loop's reference, only call it (on Task.blocking's helper thread), only give it up
define weak_odr void @zs_clo_run(ptr %c) {
entry:
  %cp = getelementptr { i_W, ptr }, ptr %c, i32 0, i32 1
  %code = load ptr, ptr %cp
  call {} %code(ptr %c, {} zeroinitializer)
  call void @zs.drop.clo(ptr %c)
  ret void
}

define weak_odr void @zs_clo_call(ptr %c) {
entry:
  %cp = getelementptr { i_W, ptr }, ptr %c, i32 0, i32 1
  %code = load ptr, ptr %cp
  call {} %code(ptr %c, {} zeroinitializer)
  ret void
}

define weak_odr void @zs_clo_drop(ptr %c) {
entry:
  call void @zs.drop.clo(ptr %c)
  ret void
}
"""

/// zs.dup and zs.release in a program with threads, in place of the prelude's: a shared object's
/// count (negative) changes atomically, and its last reference frees it. The count is read
/// atomically, since another thread may be changing a shared one; a thread-local count only this
/// thread changes.
let threadedDup = """define private void @zs.dup(ptr %p) alwaysinline {
entry:
  %rc = load atomic i32, ptr %p monotonic, align 4
  %local = icmp sgt i32 %rc, 0
  br i1 %local, label %inc, label %other
inc:
  %n = add i32 %rc, 1
  store i32 %n, ptr %p
  br label %done
other:
  %shared = icmp slt i32 %rc, 0
  br i1 %shared, label %atomic, label %done
atomic:
  %old = atomicrmw sub ptr %p, i32 1 monotonic
  br label %done
done:
  ret void
}"""

let threadedRelease = """define private i1 @zs.release(ptr %p) alwaysinline {
entry:
  %rc = load atomic i32, ptr %p monotonic, align 4
  %last = icmp eq i32 %rc, 1
  br i1 %last, label %yes, label %no
yes:
  ret i1 true
no:
  %more = icmp sgt i32 %rc, 1
  br i1 %more, label %dec, label %other
dec:
  %n = sub i32 %rc, 1
  store i32 %n, ptr %p
  ret i1 false
other:
  %shared = icmp slt i32 %rc, 0
  br i1 %shared, label %atomic, label %keep
atomic:
  %old = atomicrmw add ptr %p, i32 1 acq_rel
  %gone = icmp eq i32 %old, -1
  ret i1 %gone
keep:
  ret i1 false
}"""
