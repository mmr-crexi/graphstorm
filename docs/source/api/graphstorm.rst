.. _apigraphstorm:

.. currentmodule:: graphstorm

graphstorm
============

    The ``graphstorm`` package contains a set of functions for environment setup.
    Users can directly use the following code to use these functions.

    >>> import graphstorm as gs
    >>> gs.initialize(ip_config="/tmp/ip_list.txt", backend="gloo")
    >>> gs.setup_device(local_rank)

.. autosummary::
    :toctree: ../generated/
    :nosignatures:

    gsf.initialize
    utils.setup_device
