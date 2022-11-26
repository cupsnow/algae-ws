#!/usr/bin/env python3

import sys
import os
import json
import logging
import argparse

# import builder/builder.sh
from builder import builder

logging.basicConfig(level=logging.NOTSET,
                    format="[%(asctime)s][%(levelname)s][%(name)s][%(funcName)s][#%(lineno)d]%(message)s")

logger = logging.getLogger("configure")

app_cfg = {
    "name": "algae",
    "version": "0.1.2",
    "hardware": "bpi-0.1.1",
    "projdir": os.getcwd()
}


def populate():
	cfg = {k: app_cfg[k] for k in ["name", "version", "hardware"]}
	logger.debug(f"cfg: {cfg}")
	cfg_jstr = json.dumps(cfg)
	fn = os.path.join(app_cfg["projdir"], "prebuilt/common/etc/algae.json")
	with open(fn, "w") as f:
	f.write(cfg_jstr)
	print(f"Generated {fn}: {cfg_jstr}")


def main(argv=sys.argv):
	argc = len(argv)
	argparser = argparse.ArgumentParser(prog=os.path.basename(argv[0]),
			formatter_class=argparse.ArgumentDefaultsHelpFormatter,
			description="Configure project")
    argparser.add_argument("--populate", help="Populate configurations",
			action="store_true")

	if argc <= 1:
		# output simple usage
		argparser.print_usage()
		sys.exit(0)

	args = argparser.parse_args(argv[1:])
	logger.debug("argc: {}, argv: {}".format(argc, args))

	if args.populate:
		populate()


if __name__ == "__main__":
    if ipy := builder.guess_ipy():
        logger.debug("guess ipython {}".format(ipy))
        argv = ["configure.py", "--help"]
        main(argv)
    else:
        main(sys.argv)
