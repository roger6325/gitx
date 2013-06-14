//
//  PBGitSubmodule.h
//  GitX
//
//  Created by Seth Raphael on 9/14/12.
//
//

#import <Foundation/Foundation.h>
#import <ObjectiveGit/ObjectiveGit.h>


@interface PBGitSubmodule : NSObject

@property (nonatomic, assign) git_submodule* submodule;
@property (nonatomic, strong) NSString* workingDirectory;

@property (nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) NSString *name;

@end
