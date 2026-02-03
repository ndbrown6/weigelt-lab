from abc import ABCMeta, abstractmethod
import os
import re
import datetime
import sys
import signal
import tempfile
import random
import time
import subprocess

DEVNULL = open(os.devnull, 'wb')


def time2secs(s):
    x = time.strptime(s, '%H:%M:%S')
    return datetime.timedelta(hours=x.tm_hour,
                              minutes=x.tm_min,
                              seconds=x.tm_sec).total_seconds()


def secs2time(s):
    m, s = divmod(s, 60)
    h, m = divmod(m, 60)
    return "%02d:%02d:%02d" % (h, m, s)


def human2bytes(s):
    """
    >>> human2bytes('1M')
    1048576
    >>> human2bytes('1G')
    1073741824
    """
    symbols = ('B', 'K', 'M', 'G', 'T', 'P', 'E', 'Z', 'Y')
    num, letter = re.match(r"([0-9.]+)([A-Za-z])", s).group(1, 2)
    letter = letter.upper()
    assert letter in symbols
    num = float(num)
    prefix = {symbols[0]: 1}
    for i, s in enumerate(symbols[1:]):
        prefix[s] = 1 << (i+1)*10
    return int(num * prefix[letter])


def bytes2human(n, format="%(value)i%(symbol)s"):
    """
    >>> bytes2human(10000)
    '9K'
    >>> bytes2human(100001221)
    '95M'
    """
    symbols = ('B', 'K', 'M', 'G', 'T', 'P', 'E', 'Z', 'Y')
    prefix = {}
    for i, s in enumerate(symbols[1:]):
        prefix[s] = 1 << (i+1)*10
    for symbol in reversed(symbols[1:]):
        if n >= prefix[symbol]:
            value = float(n) / prefix[symbol]
            return format % locals()
    return format % dict(symbol=symbols[0], value=n)


class Job:
    __metaclass__ = ABCMeta

    _kill_now = False

    def __init__(self, out_file=None):
        self.out_file = out_file

    @abstractmethod
    def check_file(self, max_retry=10):
        pass

    @abstractmethod
    def run_job(self):
        pass

    @abstractmethod
    def wait(self):
        pass

    @abstractmethod
    def is_finished(self):
        pass

    def _local_check_file(self, max_retry=10):
        for attempt in range(max_retry):
            try:
                local_file_size = int(
                    subprocess.check_output('stat -c%s "{}"'.format(
                        os.path.abspath(self.out_file)), stderr=DEVNULL, shell=True).strip())
                return local_file_size
            except:
                sys.stderr.write("Unable to stat {} locally\n".format(os.path.abspath(self.out_file)))
                time.sleep(10)
            else:
                sys.stderr.write("max retries for local file size check\n")
                return 0
            if self._kill_now:
                return 0


class LocalJob(Job):

    def __init__(self, job_script, shell=None, out_file=None, log_file=None):
        Job.__init__(self, out_file)
        self.job_script = job_script
        self.log_file = log_file
        self.retval = None
        self.shell = shell

    def run_job(self):
        job_script_file = tempfile.NamedTemporaryFile(mode='w',
                                                      suffix='.sh', delete=False)
        job_script_file.write(self.job_script)
        job_script_file.close()
        os.chmod(job_script_file.name, 0o555)
        with open(self.log_file, 'w') as err:
            self.process = subprocess.Popen([self.shell, job_script_file.name],
                                            stderr=err, stdout=err, shell=False)

    def wait(self):
        self.retval = self.process.wait()
        return self.retval

    def is_finished(self):
        return self.retval is not None and self.retval == 0

    def check_file(self, max_retry=10):
        time.sleep(10)
        if self.out_file is None:
            return True
        local_file_size = super(LocalJob, self)._local_check_file(max_retry)
        if local_file_size == 0:
            return False
        else:
            return True


class ClusterJob(Job):
    __metaclass__ = ABCMeta

    def __init__(self, out_file=None, remote_check_servers=None):
        Job.__init__(self, out_file)
        self.remote_check_servers = remote_check_servers
        signal.signal(signal.SIGINT, self.__exit_gracefully)
        signal.signal(signal.SIGTERM, self.__exit_gracefully)

    def check_file(self, max_retry=10):
        """ checks the file size of file f on remote servers and returns True
        if it matches local file size and also local file size > 0
        """
        time.sleep(10)
        if self.out_file is None:
            return True
        local_file_size = super(ClusterJob, self)._local_check_file(max_retry)
        if local_file_size == 0:
            return False
        if self.remote_check_servers is not None:
            for server in self.remote_check_servers:
                if not self._remote_check_file(local_file_size, server,
                                               max_retry):
                    return False
        return local_file_size > 0

    def _remote_check_file(self, local_file_size, server, max_retry):
        for attempt in range(max_retry):
            try:
                remote_file_size = int(subprocess.
                                       check_output('ssh {} stat -c%s "{}"'.
                                                    format(server, os.path.abspath(self.out_file)),
                                                    stderr=DEVNULL, shell=True).strip())
                if remote_file_size != local_file_size:
                    raise ValueError(
                        "{}: remote file size != local file size: {} != {}"
                        .format(server,
                                remote_file_size,
                                local_file_size))
                break
            except ValueError as e:
                sys.stderr.write(e + "\n")
                time.sleep(10)
            except:
                sys.stderr.write("{}: failed remote file size check\n"
                                 .format(server))
                time.sleep(10)
            else:
                sys.stderr.write("max connection retries for "
                                 "remote file size check\n")
                return False
            if self._kill_now:
                return False
        return True

    def __exit_gracefully(self, signum, frame):
        print("received interrupt")
        self._kill_now = True

    @abstractmethod
    def run_job(self):
        pass

    @abstractmethod
    def wait(self):
        pass


class LSFJob(ClusterJob):

    def __init__(self, job_script, qsub_args='', out_file=None,
                 remote_check_servers=None):
        ClusterJob.__init__(self, out_file, remote_check_servers)
        self.job_script = job_script
        if qsub_args is not None:
            self.qsub_args = qsub_args
        else:
            self.qsub_args = ''

    def run_job(self):
        """ bsub job
        """
        self.job_script_file = tempfile.NamedTemporaryFile(mode='w',
                                                           suffix='.sh',
                                                           delete=False)
        self.job_script_file.write(self.job_script)
        self.job_script_file.close()
        os.chmod(self.job_script_file.name, 0o555)

        cmd = "bsub -K {args} {script}".format(args=self.qsub_args, script=self.job_script_file.name)
        self.process = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True)

    def wait(self):
        self.retval = self.process.wait()
        return self.retval

    def is_finished(self):
        return self.retval is not None and self.retval == 0


class SlurmJob(ClusterJob):

    def __init__(self, job_script, sbatch_args='', out_file=None,
                 remote_check_servers=None):
        ClusterJob.__init__(self, out_file, remote_check_servers)
        self.job_script = job_script
        if sbatch_args is not None:
            self.sbatch_args = sbatch_args
        else:
            self.sbatch_args = ''
        self.retval = None

    def run_job(self):
        """ sbatch job and spawn scontrol to monitor it
        """
        self.job_script_file = tempfile.NamedTemporaryFile(mode='w',
                                                           suffix='.sh',
                                                           delete=False)
        self.job_script_file.write(self.job_script)
        self.job_script_file.close()
        os.chmod(self.job_script_file.name, 0o555)

        # Submit the job with sbatch and use --wait to block until completion
        cmd = "sbatch --wait {args} {script}".format(args=self.sbatch_args, script=self.job_script_file.name)
        self.process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
        
        # Read the job ID from stdout immediately (sbatch prints it before blocking)
        stdout_line = self.process.stdout.readline().decode()
        match = re.search(r'Submitted batch job (\d+)', stdout_line)
        if match:
            self.job_id = match.group(1)
        else:
            # If we can't get the job ID, still continue
            self.job_id = None

    def wait(self):
        """Wait for job to complete. sbatch --wait will block until job finishes."""
        if self._kill_now:
            sys.stderr.write("registering job for deletion\n")
            if self.job_id:
                subprocess.Popen("scancel {}".format(self.job_id), shell=True)
            self.retval = 1
            return self.retval
        
        # Wait for sbatch --wait to complete
        sbatch_retcode = self.process.wait()
        
        # Get the actual job exit status using sacct if we have a job ID
        if self.job_id:
            try:
                # Wait a moment for job accounting to be updated
                time.sleep(2)
                # sacct format: JobID|State|ExitCode
                sacct_cmd = "sacct -j {} -n -P -o JobID,State,ExitCode".format(self.job_id)
                sacct_output = subprocess.check_output(sacct_cmd, shell=True, stderr=DEVNULL).decode()
                
                # Parse sacct output - look for the main job (not .batch or .extern)
                for line in sacct_output.strip().split('\n'):
                    fields = line.split('|')
                    if len(fields) >= 3:
                        job_id_field = fields[0]
                        # Skip .batch and .extern job steps, look for the main job ID
                        if job_id_field == self.job_id:
                            state = fields[1]
                            exit_code = fields[2]
                            # ExitCode format is typically "0:0" where first number is exit code
                            if ':' in exit_code:
                                self.retval = int(exit_code.split(':')[0])
                            else:
                                self.retval = int(exit_code) if exit_code.isdigit() else sbatch_retcode
                            break
                else:
                    # If we couldn't parse sacct output, fall back to sbatch return code
                    self.retval = sbatch_retcode
            except:
                # If sacct fails, use sbatch return code
                self.retval = sbatch_retcode
        else:
            # No job ID, use sbatch return code
            self.retval = sbatch_retcode
            
        return self.retval

    def is_finished(self):
        return self.retval is not None and self.retval == 0


class PBSJob(ClusterJob):

    def __init__(self, job_script, qsub_args='', out_file=None,
                 poll_interval=10, remote_check_servers=None):
        ClusterJob.__init__(self, out_file, remote_check_servers)
        self.poll_interval = poll_interval
        self.job_script = job_script
        if qsub_args is not None:
            self.qsub_args = qsub_args
        else:
            self.qsub_args = ''

    def run_job(self):
        """ qsub job
        """
        self.job_script_file = tempfile.NamedTemporaryFile(mode='w',
                                                           suffix='.sh',
                                                           delete=False)
        self.job_script_file.write(self.job_script)
        self.job_script_file.close()
        os.chmod(self.job_script_file.name, 0o555)

        cmd = "qsub"
        cmd += " " + self.qsub_args
        cmd += " " + self.job_script_file.name
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True)
        proc.wait()
        if proc.returncode != 0:
            raise Exception('unable to qsub job: {}'.format(cmd))
        self.job_id = proc.stdout.read().rstrip()
        self.update_qstat()

    def update_qstat(self):
        """ update the job state using qstat
        """
        self.qstat = {}
        proc = subprocess.Popen(['qstat', '-f', self.job_id], stdout=subprocess.PIPE)
        proc.wait()
        job_id_line = proc.stdout.readline().strip()
        if proc.returncode != 0 or self.job_id not in job_id_line:
            raise Exception('unable to qstat job id: {}'.format(self.job_id))
        self.qstat = self._parse_qstat(proc.stdout)

    def _parse_qstat(self, f):
        qstat = {}
        while True:
            line = f.readline()
            if not line:
                break
            line = line.strip()
            mo = re.search(r'([^=]+) = (.+)', line)
            if not mo:
                continue
            k = mo.group(1)
            v = mo.group(2)
            while line.endswith(','):
                line = f.readline()
                if not line:
                    break
                line = line.strip()
                v += line
            if v.isdigit():
                qstat[k] = int(v)
            else:
                qstat[k] = v
        return qstat

    def wait(self):
        """ wait for job to finish and return qstat exit_status
        """
        while True:
            self.update_qstat()
            if self.qstat['job_state'] == "C":
                break
            if self.qstat['job_state'] == "H" or self.qstat['job_state'] == "S":
                raise Exception('job halted')
            time.sleep(random.randint(self.poll_interval, self.poll_interval + 20))
            if self._kill_now:
                sys.stderr.write("registering job for deletion\n")
                subprocess.Popen("qdel {}".format(self.job_id), shell=True)
                self.update_qstat()
                break
        if 'exit_status' in self.qstat:
            return self.qstat['exit_status']
        else:
            return 99

    def is_finished(self):
        return self.qstat is not None and 'exit_status' in self.qstat and \
            self.qstat['exit_status'] == 0 and not self._kill_now

    def hit_mem_limit(self):
        """ True if mem limit was hit
        """
        try:
            mem_used = human2bytes(self.qstat['resources_used.mem'])
            mem_alloc = human2bytes(self.qstat['Resource_List.mem'])
            return mem_used + human2bytes('100M') > mem_alloc
        except:
            return False

    def hit_walltime_limit(self):
        """ True if walltime limit hit
        """
        try:
            walltime_used = time2secs(self.qstat['resources_used.walltime'])
            walltime_alloc = time2secs(self.qstat['Resource_List.walltime'])
            return walltime_used + 5 > walltime_alloc
        except:
            return False

    def restart(self, resource_multiplier):
        """ restart with higher reqs if req'd
        """
        mem = human2bytes(self.qstat['Resource_List.mem'])
        walltime = self.qstat['Resource_List.walltime']
        if self.hit_walltime_limit():
            walltime_secs = time2secs(walltime) * resource_multiplier
            walltime = secs2time(walltime_secs)
            sys.stderr.write("increased walltime to {}\n".format(walltime))
        if self.hit_mem_limit():
            mem = int(mem * resource_multiplier)
            sys.stderr.write("increased mem to {}\n".format(bytes2human(mem)))

        if self.qsub_args is not None and self.qsub_args.find('-l mem') != -1:
            self.qsub_args = re.sub(r'-l mem=(\S+)', '-l mem={}'.format(mem), self.qsub_args)
        else:
            self.qsub_args += ' -l mem={}'.format(mem)

        if self.qsub_args is not None and self.qsub_args.find('-l walltime') != -1:
            self.qsub_args = re.sub(r'-l walltime=(\S+)', '-l walltime={}'.format(walltime), self.qsub_args)
        else:
            self.qsub_args += ' -l walltime={}'.format(walltime)

        self.run_job()
