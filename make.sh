export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

mkdir -p docs
for file in $(basename -s .rst *.rst); do
	./rst2html.py $file.rst docs/$file.html
done
