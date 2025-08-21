import os
import glob

# Execute all python files in the evaluation directory
eval_dir = os.path.join(os.getenv('DOCKER_SRC_DIRECTORY', '../../src'), 'evaluation')
for py_file in glob.glob(os.path.join(eval_dir, '*.py')):
    if not py_file.endswith('main.py'):  # Don't execute self
        exec(open(py_file).read(), globals())