export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

FILES=(dxxxx-allocate_unique dxxxx-deduction-guides)

mkdir -p docs
for file in dxxxx-allocate_unique dxxxx-deduction-guides; do
	./rst2html.py $file.rst docs/$file.html
done
