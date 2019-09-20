# Vertbaudet Tools


### Requirements

You need to have node


### Installation
Install required node packages
```
npm install
```

### Use
After the symlink done, go in the target directory and do :
```
vb-tools
```

### Dev
A gulp watcher will generate the js from coffee, you just need to do "npm start" to test with the test files.
```
gulp
```

Test the app on test files.
```
npm start
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

You can use gulp too :
```
gulp
```
This command will watch the coffee file.