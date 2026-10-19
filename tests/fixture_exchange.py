"""Bounded portable native-fixture pipe exchange and unconditional retirement."""
import os
import queue
import subprocess
import threading
import time

class FixtureExchange:
    """Bound the entire pipe exchange, including reads, then retire and reap the child."""
    def __init__(self, command, timeout=15, output_bound=2*1048576, error_bound=65536, pass_fds=()):
        self.process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,pass_fds=pass_fds)
        self.deadline=time.monotonic()+timeout
        self.output_bound=output_bound
        self.error_bound=error_bound
        self.events=queue.Queue(maxsize=64)
        self.buffer=bytearray()
        self.errors=bytearray()
        self.failures=[]
        self.eof=False
        self.stop=threading.Event()
        self.readers=[]
        for stream, output in ((self.process.stdout,True),(self.process.stderr,False)):
            thread=threading.Thread(target=self._pump,args=(stream,output),daemon=True)
            thread.start();self.readers.append(thread)

    def _push(self, item):
        while not self.stop.is_set():
            try:self.events.put(item,timeout=0.1);return
            except queue.Full:pass

    def _pump(self, stream, output):
        size=0
        try:
            while not self.stop.is_set():
                chunk=os.read(stream.fileno(),65536)
                if not chunk:break
                size+=len(chunk)
                if size>(self.output_bound if output else self.error_bound):
                    raise AssertionError('native fixture exceeded output bound')
                if output:self._push(chunk)
                else:self.errors.extend(chunk)
        except BaseException as error:
            self.failures.append(error)
            self._push(error)
        finally:
            if output:self._push(None)

    def _remaining(self):
        left=self.deadline-time.monotonic()
        if left<=0:raise TimeoutError('native fixture exchange timed out')
        return left

    def _next(self):
        try:item=self.events.get(timeout=self._remaining())
        except queue.Empty:raise TimeoutError('native fixture exchange timed out') from None
        if isinstance(item,BaseException):raise item
        if item is None:self.eof=True
        else:self.buffer.extend(item)

    def read(self, length):
        assert 0<=length<=1048576+256,length
        while len(self.buffer)<length:
            if self.eof:raise AssertionError(('early fixture EOF',length,len(self.buffer),self.process.poll(),bytes(self.errors)))
            self._next()
        result=bytes(self.buffer[:length]);del self.buffer[:length]
        return result

    def send(self, byte):
        assert len(byte)==1
        self._remaining()
        self.process.stdin.write(byte);self.process.stdin.flush()

    def finish(self):
        self.process.stdin.close()
        while not self.eof:self._next()
        self.process.wait(timeout=self._remaining())
        for reader in self.readers:
            reader.join(timeout=self._remaining())
            if reader.is_alive():raise TimeoutError('native fixture output did not close')
        if self.failures:raise self.failures[0]
        return bytes(self.buffer),bytes(self.errors)

    def __enter__(self):return self

    def __exit__(self, kind, value, traceback):
        try:
            if self.process.poll() is None:self.process.kill()
            self.process.wait(timeout=5)
        finally:
            self.stop.set()
            for reader in self.readers:reader.join(timeout=0.5)
            for stream in (self.process.stdin,self.process.stdout,self.process.stderr):stream.close()

