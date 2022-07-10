#!/usr/bin/env python3
#%%
# define functions

import sys, os, json, logging, argparse

logging.basicConfig(level=logging.NOTSET, format="[%(asctime)s][%(levelname)s][%(name)s][%(funcName)s][#%(lineno)d]%(message)s")

logger = logging.getLogger("configure")

projDir = os.getcwd()

sys.path.append(os.path.join(projDir, "builder"))
from builder import *

appCfg = {
	"deviceName": "algae",
	"version": "0.1.2",
	"hardware": "bpi",
	"hardwareVersion": "0.1.1",
	"model": "bbq3",
	"modelSerial": "1",
	"buildDir": "build",
	"buildDir2": "../build",
	"pkgDir": "package",
	"pkgDir2": "..",
}

def populate():
	jCfg = json.dumps(appCfg)
	print("\nappCfg in json:\n{}".format(jCfg))
	fn = os.path.join(projDir, "prebuilt/common/etc/algae.json")
	with open(fn, "w") as f:
		f.write(jCfg)

#%%
# Start main

def main (argv = sys.argv):
	argparser = argparse.ArgumentParser(prog=argv[0], description="Configure project")
	argparser.add_argument("--populate", help="Populate configurations", action="store_true")

	argc = len(argv)
	if argc <= 1:
		argparser.print_usage()
		sys.exit(0)
	args = argparser.parse_args(argv[1:])
	logger.debug("argc: {}, argv: {}".format(argc, args))

	if args.populate:
		populate()

if __name__ == "__main__":
	# jupyter?
	ipy = guessIpy()
	if ipy:
		logger.debug("guess ipython {}".format(ipy))
		argv = ["configure.py", "--help"]
		main(argv)
	else:
		main(sys.argv)

