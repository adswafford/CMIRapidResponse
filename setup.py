#!/usr/bin/env python

# ----------------------------------------------------------------------------
# Copyright (c) 2017-, Jose Antonio Navas Molina.
#
# Distributed under the terms of the Modified BSD License.
#
# The full license is in the file LICENSE, distributed with this software.
# ----------------------------------------------------------------------------

from setuptools import setup
from glob import glob

__version__ = "0.1.0-dev"


classes = """
    Development Status :: 3 - Alpha
    License :: OSI Approved :: BSD License
    Topic :: Scientific/Engineering :: Bio-Informatics
    Topic :: Software Development :: Libraries :: Application Frameworks
    Topic :: Software Development :: Libraries :: Python Modules
    Programming Language :: Python
    Programming Language :: Python :: 3.5
    Programming Language :: Python :: Implementation :: CPython
    Operating System :: POSIX :: Linux
    Operating System :: MacOS :: MacOS X
"""

with open('README.md') as f:
    long_description = f.read()

classifiers = [s.strip() for s in classes.split('\n') if s]

setup(name='CMIRapidResponse',
      version=__version__,
      long_description=long_description,
      license="BSD",
      description='CMI Rapid Response',
      author="Jose Antonio Navas Molina",
      author_email="josenavasmolina@gmail.com",
      url='https://github.com/josenavas/CMIRapidResponse',
      test_suite='nose.collector',
      packages=['cmirr'],
      include_package_data=True,
      package_data={'cmirr': ['support_files/template.html']},
      scripts=glob('scripts/*'),
      extras_require={'test': ["nose >= 0.10.1", "pep8"]},
      install_requires=['click == 6.7'],
      classifiers=classifiers)
