# Vertbaudet Lazy Tool

### Introduction

Un système de "lazy loading" exite sur le site vertbaudet.fr, un script JS dédié est présent sur toutes les pages du site.

L'outil ici présent permet d'installer automatiquement les attributs de lazy loading sur les balises images.
Il gère également l'installation du lazy loading de background, il modifie alors les fichier HTML et le fichier SCSS.
Le système complète également automatiquement les attributs "alt" des images, si ils sont absents ou vides.

Exemple :
```
<img alt="" src="logo.png" />
```
va être tranformé en :
```
<img alt="logo" src="data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==" data-loaded="false" onload="javascript:LazyLoadHelper.loadElement(this);" data-image='{"src": "logo.png"}'/>
```


### Installation

#### Requirements

You need to have NodeJS

https://nodejs.org/fr/


#### Install dependencies

Install required node packages
```
npm install
```


#### Symlink

First, clone this repository.
To prepare symlink, go in the directory of this project and do :
```
sudo npm link
```

After that, go in the directory of another project like "Vertbaudet"
and do :
```
npm link ../vertbaudet-lazy-tool
```

("../vertbaudet-lazy-tool" is the path from the "Vertbaudet" directory)

Now you can directly use "vb-tools" command from the other project

(If you work on the "bin" system, maybe you should unlink and link again)


### Use
After the symlink done, go in the target directory and do :
```
vb-tools
```

To ignore SCSS analyse :
```
vb-tools --noscss
```

To ignore a specific class :
```
vb-tools --ignore-class classname
```
(This can be useful when a class is built in a JS file)


### Build / Dev
To generate the js file from the coffee file :
```
npm run build
```


You can use gulp too :
```
gulp
```
This command will watch the coffee file.


Test the app on local test files :
```
npm start
```