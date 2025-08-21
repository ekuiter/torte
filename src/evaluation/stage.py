import os
from os import getenv
from os.path import join
from glob import glob

try:
    EXPERIMENT
except NameError:
    EXPERIMENT = None

def get_stages_directory(experiment=EXPERIMENT):
    if getenv('INSIDE_STAGE'):
        raise ValueError("Not available inside docker container")
    base_dir = join('..', '..')
    experiment_dirs = glob(join(base_dir, f'*stages*{experiment}*')) if experiment else None
    if experiment_dirs:
        return experiment_dirs[0]
    else:
        return join(base_dir, 'stages')

def get_stage_directory(stage, key='main', experiment=EXPERIMENT):
    if getenv('INSIDE_STAGE'):
        return join("/home", "input", key)
    else:
        stages_directory = get_stages_directory(experiment)
        matched_stages = glob(join(stages_directory, f'*_{stage}'))
        if not matched_stages:
            raise ValueError(f"No stage '{stage}' found in {stages_directory}")
        stage = matched_stages[0].split('/')[-1]
        return join(stages_directory, stage)