#!/bin/bash

source ./scripts/log-colors.sh
log_color "cyan" "Running Installer Owner File Resync\n"

echo $GITHUB_TOKEN

####################
## ENV VARIABLES
####################

export BASE_DIR=$(pwd)
export ORG=${ORG:-"dislbenn"}

export OWNERS_FILE_PATH="resources/OWNERS"
export REPOS_FILE_PATH="resources/repos.yaml"

export CREATE_RESYNC_BRANCH_REQUIRED=false

####################
## FUNCTIONS
####################

cleanup () {
    echo -e "Removing repository: $1\n"
    rm -rf $1
}

resync_branch_exist() {
    git ls-remote --exit-code --heads origin $1

    if [[ $? -eq 0 ]]; then
        echo -e "\nResync branch already exist: $1"
        CREATE_RESYNC_BRANCH_REQUIRED=false

    else
        echo -e "\nResync branch does not exist: $1"
        CREATE_RESYNC_BRANCH_REQUIRED=true
    fi
}

create_resync_branch() {
    echo -e "Creating new branch: $1"
    git checkout -b $1
}

fetch_release_branch () {
    if ! git ls-remote -q origin $RELEASE_BRANCH &> /dev/null; then
        echo -e "Release branch does not exist: $RELEASE_BRANCH"
        return 1

    else
        git checkout $RELEASE_BRANCH
    fi
}

fetch_repository () {
    if [ ! -d $1 ]; then
        echo -e "Fetching repository: $1\n"
        git clone git@github.com:$ORG/$1

        if [ $? -ne 0 ]; then
            echo -e "Failed to clone the repository: $ORG/$1"
            return 1
        fi
    else
        return 0
    fi
}

owners_file_check () {
    # Clone repositories to fetch OWNERS file.
    fetch_repository $1 && cd $1
    gh repo set-default $ORG/$1

    for RELEASE_BRANCH in $(yq ".repos[] | select(.name == \"$1\") | .release-branches[].branch" $BASE_DIR/$REPOS_FILE_PATH); do
        RESYNC_BRANCH=resync-owners-$RELEASE_BRANCH

        echo -e "\nChecking to see if the resync branch already exist: $RESYNC_BRANCH"
        resync_branch_exist $RESYNC_BRANCH

        if [[ $CREATE_RESYNC_BRANCH_REQUIRED = false ]]; then
            echo -e "Skipping resync for $RELEASE_BRANCH, since $RESYNC_BRANCH already exists"
            continue
        fi

        echo -e "\nChecking out release branch: $RELEASE_BRANCH"
        fetch_release_branch $RELEASE_BRANCH && echo -e

        if [ ! -f "OWNERS" ]; then
            echo -e "OWNERS file doesn't exist... Creating OWNERS file for release branch\n"
            cp $BASE_DIR/$OWNERS_FILE_PATH .

        else
            echo -e "Found OWNERS file on release branch"
                
            if ! cmp $BASE_DIR/$OWNERS_FILE_PATH OWNERS; then
                echo -e "Resync required for release branch\n" && create_resync_branch $RESYNC_BRANCH

                echo -e "================================================================"
                echo -e "$BASE_DIR/$OWNERS_FILE_PATH\n"
                log_color "blue" "$(cat $BASE_DIR/$OWNERS_FILE_PATH)"
                
                echo -e "\n$(pwd)/OWNERS\n"
                log_color "yellow" "$(cat OWNERS)"
                echo -e "================================================================\n"
                
                cp $BASE_DIR/$OWNERS_FILE_PATH OWNERS

                git add OWNERS
                git commit -sm "Resynced OWNERS file for $RELEASE_BRANCH"
                git push --set-upstream origin $RESYNC_BRANCH

                gh pr create -t "Resynced OWNERS file for $RELEASE_BRANCH" -b "Updated OWNERS to match source of truth" -B $RELEASE_BRANCH -R $ORG/$1
            fi
        fi
    done
}

validate_file() {
    if [ ! -f $OWNERS_FILE_PATH ]; then
        echo -e "ERROR: \"$OWNERS_FILE_PATH\" file does not exist. (OWNERS file is required to continue. Please create a new OWNERS file and try again)"
        exit 1
    fi

    if [ ! -f $REPOS_FILE_PATH ]; then
        echo -e "ERROR: \"$REPOS_FILE_PATH\" file does not exist. (repos.yaml file is required to continue. Please create a new a \"repos.yaml\" file and try again)"
        exit 1
    fi
}

validate_file
for REPO in $(yq ".repos[].name" $REPOS_FILE_PATH); do
    echo -e "\033[0;33mPreparing to check repositories: $REPO\033[0m"
    echo "================================================"

    owners_file_check $REPO
    
    cd $BASE_DIR && echo -e
    cleanup $REPO
done

echo -e "Exiting program..."
exit 0
