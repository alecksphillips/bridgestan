from typing import List
import os
import subprocess
from pathlib import Path
import platform

PYTHON_FOLDER = Path(__file__).parent.parent

MAKE = os.getenv(
    "MAKE",
    "make" if platform.system() != "Windows" else "mingw32-make",
)

BRIDGESTAN_PATH = os.getenv("BRIDGESTAN", str(PYTHON_FOLDER.parent))
CMDSTAN_PATH = os.getenv("CMDSTAN", "")
if CMDSTAN_PATH is None:
    try:
        CMDSTAN_PATH = sorted(
            (filter(Path.is_dir, (Path.home() / ".cmdstan").iterdir()))
        )[0]
    except:
        pass


def set_cmdstan_path(path: str) -> None:
    """Set the path to CmdStan used by BridgeStan.

    By default this is set to the value of the environment
    variable ``CMDSTAN``, or to the newest installation available
    in ``~/.cmdstan/``.
    """
    global CMDSTAN_PATH
    CMDSTAN_PATH = path


def set_bridgestan_path(path: str) -> None:
    """Set the path to BridgeStan.

    This should point to the top-level folder of the repository.

    By default this is set to the value of the environment
    variable ``BRIDGESTAN``, or to the folder above the location
    of this package (which, assuming a source installation, corresponds
    to the repository root).
    """
    global BRIDGESTAN_PATH
    verify_bridgestan_path(path)
    BRIDGESTAN_PATH = path


def verify_bridgestan_path(path: str) -> None:
    folder = Path(path).resolve()
    if not folder.exists():
        raise ValueError(
            f"BridgeStan folder '{folder}' does not exist!\n"
            "If you need to set a different location, call 'set_bridgestan_path()'"
        )
    makefile = folder / "Makefile"
    if not makefile.exists():
        raise ValueError(
            f"BridgeStan folder '{folder}' does not "
            "contain file 'Makefile', please ensure it is built properly!\n"
            "If you need to set a different location, call 'set_bridgestan_path()'"
        )


def generate_so_name(model: Path[str]):
    name = model.stem
    return model.with_stem(f"{name}_model").with_suffix(".so")


def compile_model(stan_file: str, args: List[str] = []) -> Path[str]:
    """
    Run BridgeStan's Makefile on a ``.stan`` file, creating the ``.so``
    used by the StanModel class.

    This function assumes that the paths to BridgeStan and CmdStan
    are both valid. These can be set with :func:`set_bridgestan_path`
    and :func:`set_cmdstan_path` if their default values do not
    match your system configuration.

    :param stan_file: A path to a Stan model file.
    :param args: A list of additional arguments to pass to Make.
        For example, ``["STAN_THREADS=True"]`` will enable
        threading for the compiled model.
    :raises FileNotFoundError: If `stan_file` does not exist.
    :raises ValueError: If BridgeStan cannot be located.
    :raises RuntimeError: If compilation fails.
    """
    verify_bridgestan_path(BRIDGESTAN_PATH)

    file_path = Path(stan_file).resolve()
    if not file_path.exists:
        raise FileNotFoundError(f"File '{stan_file}' does not exist")
    if file_path.suffix != ".stan":
        raise ValueError(f"File '{stan_file}' does not end in .stan")

    output = generate_so_name(file_path)
    cmdstan = str(Path(CMDSTAN_PATH).resolve()).replace("\\", "/")
    cmd = [MAKE, f"CMDSTAN={cmdstan}/"] + args + [str(output)]
    proc = subprocess.run(
        cmd, cwd=BRIDGESTAN_PATH, capture_output=True, text=True, check=False
    )

    if proc.returncode:
        error = (
            f"Command {' '.join(cmd)} failed with code {proc.returncode}.\n"
            f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
        if "stanc" in error:
            error += (
                "\nIf CmdStan is already installed, you may "
                "need to set the location with set_cmdstan_path()"
            )

        raise RuntimeError(error)
    return output
