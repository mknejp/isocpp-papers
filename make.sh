export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

FILES=(dxxxx-allocate_unique)

for file in ${FILES}; do
	rst2html.py $file.rst $file.html
done
