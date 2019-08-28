# Vertbaudet Tools


### Requirements

You need to have node


### Installation

Install required node packages

```
npm install
```


### Symlink

First, clone this repository.
To prepare symlink, go in the directory of this project and do :
```
sudo npm link
```

After that, go in the directory of another project like "Vertbaudet"
and do :
```
npm link ../vertbaudet-tools
```

("../vertbaudet-tools" is the path from the "Vertbaudet" directory)

Now you can directly use "vb-tools" command from the other project

(If you work on the "bin" system, maybe you should unlink and link again)


### Build
```
npm run build
```
To generate the js file from the coffee file.