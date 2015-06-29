/*
 *  BasicDrawable.mm
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 2/1/11.
 *  Copyright 2011-2015 mousebird consulting
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 */

#import "GLUtils.h"
#import "BasicDrawableInstance.h"
#import "GlobeScene.h"
#import "UIImage+Stuff.h"
#import "SceneRendererES.h"
#import "TextureAtlas.h"

using namespace Eigen;

namespace WhirlyKit
{

BasicDrawableInstance::BasicDrawableInstance(const std::string &name,SimpleIdentity masterID)
: Drawable(name), enable(true), masterID(masterID), requestZBuffer(false), writeZBuffer(true), startEnable(0.0), endEnable(0.0), instBuffer(0), numInstances(0)
{
}

Mbr BasicDrawableInstance::getLocalMbr() const
{
    return basicDraw->getLocalMbr();
}

unsigned int BasicDrawableInstance::getDrawPriority() const
{
    if (hasDrawPriority)
        return drawPriority;
    return basicDraw->getDrawPriority();
}

SimpleIdentity BasicDrawableInstance::getProgram() const
{
    return basicDraw->getProgram();
}

bool BasicDrawableInstance::isOn(WhirlyKitRendererFrameInfo *frameInfo) const
{
    if (minVis == DrawVisibleInvalid || !enable)
        return enable;
    
    double visVal = [frameInfo.theView heightAboveSurface];
    
    bool test = ((minVis <= visVal && visVal <= maxVis) ||
                 (maxVis <= visVal && visVal <= minVis));
    return test;
}

GLenum BasicDrawableInstance::getType() const
{
    return basicDraw->getType();
}

bool BasicDrawableInstance::hasAlpha(WhirlyKitRendererFrameInfo *frameInfo) const
{
    return basicDraw->hasAlpha(frameInfo);
}

void BasicDrawableInstance::updateRenderer(WhirlyKitSceneRendererES *renderer)
{
    return basicDraw->updateRenderer(renderer);
}

const Eigen::Matrix4d *BasicDrawableInstance::getMatrix() const
{
    return basicDraw->getMatrix();
}

void BasicDrawableInstance::addInstances(const std::vector<SingleInstance> &insts)
{
    instances.insert(instances.end(), insts.begin(), insts.end());
}

void BasicDrawableInstance::setupGL(WhirlyKitGLSetupInfo *setupInfo,OpenGLMemManager *memManager)
{
    if (instBuffer)
        return;
    
    numInstances = instances.size();
    
    if (instances.empty())
        return;

    // Note: Doing matrices, but not color
    
    int instSize = sizeof(GLfloat)*16;
    int bufferSize = instSize * instances.size();
    
    instBuffer = memManager->getBufferID(bufferSize,GL_STATIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, instBuffer);
    void *glMem = NULL;
    EAGLContext *context = [EAGLContext currentContext];
    if (context.API < kEAGLRenderingAPIOpenGLES3)
        glMem = glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
    else
        glMem = glMapBufferRange(GL_ARRAY_BUFFER, 0, bufferSize, GL_MAP_WRITE_BIT);
    unsigned char *basePtr = (unsigned char *)glMem;
    for (unsigned int ii=0;ii<instances.size();ii++,basePtr+=instSize)
    {
        Matrix4f mat = Matrix4dToMatrix4f(instances[ii].mat);
        memcpy(basePtr, (void *)mat.data(), instSize);
    }
    
    if (context.API < kEAGLRenderingAPIOpenGLES3)
        glUnmapBufferOES(GL_ARRAY_BUFFER);
    else
        glUnmapBuffer(GL_ARRAY_BUFFER);
    
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}
    
void BasicDrawableInstance::teardownGL(OpenGLMemManager *memManage)
{
    if (instBuffer)
    {
        memManage->removeBufferID(instBuffer);
        instBuffer = 0;
    }
}
    
// Used to pass in buffer offsets
#define CALCBUFOFF(base,off) ((char *)((long)(base) + (off)))

void BasicDrawableInstance::draw(WhirlyKitRendererFrameInfo *frameInfo,Scene *scene)
{
    EAGLContext *context = [EAGLContext currentContext];
    OpenGLES2Program *prog = frameInfo.program;
    
    // Pull default values
    RGBAColor thisColor = basicDraw->getColor();
    float thisMinVis,thisMaxVis;
    basicDraw->getVisibleRange(thisMinVis, thisMaxVis);
    float lineWidth = basicDraw->getLineWidth();

    // Look to overrides on this instance
    if (hasColor)
        thisColor = color;
    if (hasLineWidth)
        lineWidth = lineWidth;
    if (hasMinVis || hasMaxVis)
    {
        minVis = thisMinVis;
        maxVis = thisMaxVis;
    }
    
    // Figure out if we're fading in or out
    float fade = 1.0;
    // Note: Time based fade isn't represented in the instance.  Probably should be.

    // Deal with the range based fade
    if (frameInfo.heightAboveSurface > 0.0)
    {
        float factor = 1.0;
        if (basicDraw->minVisibleFadeBand != 0.0)
        {
            float a = (frameInfo.heightAboveSurface - minVis)/basicDraw->minVisibleFadeBand;
            if (a >= 0.0 && a < 1.0)
                factor = a;
        }
        if (basicDraw->maxVisibleFadeBand != 0.0)
        {
            float b = (maxVis - frameInfo.heightAboveSurface)/basicDraw->maxVisibleFadeBand;
            if (b >= 0.0 && b < 1.0)
                factor = b;
        }
        
        fade = fade * factor;
    }
    
    // GL Texture IDs
    bool anyTextures = false;
    std::vector<GLuint> glTexIDs;
    for (unsigned int ii=0;ii<basicDraw->texInfo.size();ii++)
    {
        const BasicDrawable::TexInfo &thisTexInfo = basicDraw->texInfo[ii];
        GLuint glTexID = EmptyIdentity;
        if (thisTexInfo.texId != EmptyIdentity)
        {
            glTexID = scene->getGLTexture(thisTexInfo.texId);
            anyTextures = true;
        }
        glTexIDs.push_back(glTexID);
    }
    
    // Model/View/Projection matrix
    prog->setUniform("u_mvpMatrix", frameInfo.mvpMat);
    prog->setUniform("u_mvMatrix", frameInfo.viewAndModelMat);
    prog->setUniform("u_mvNormalMatrix", frameInfo.viewModelNormalMat);
    prog->setUniform("u_mvpNormalMatrix", frameInfo.mvpNormalMat);
    prog->setUniform("u_pMatrix", frameInfo.projMat);
    
    // Fade is always mixed in
    prog->setUniform("u_fade", fade);
    
    // Let the shaders know if we even have a texture
    prog->setUniform("u_hasTexture", anyTextures);
    
    // If this is present, the drawable wants to do something based where the viewer is looking
    prog->setUniform("u_eyeVec", frameInfo.fullEyeVec);
    
    // The program itself may have some textures to bind
    bool hasTexture[WhirlyKitMaxTextures];
    int progTexBound = prog->bindTextures();
    for (unsigned int ii=0;ii<progTexBound;ii++)
        hasTexture[ii] = true;
    
    // Zero or more textures in the drawable
    for (unsigned int ii=0;ii<WhirlyKitMaxTextures-progTexBound;ii++)
    {
        GLuint glTexID = ii < glTexIDs.size() ? glTexIDs[ii] : 0;
        char baseMapName[40];
        sprintf(baseMapName,"s_baseMap%d",ii);
        const OpenGLESUniform *texUni = prog->findUniform(baseMapName);
        hasTexture[ii+progTexBound] = glTexID != 0 && texUni;
        if (hasTexture[ii+progTexBound])
        {
            [frameInfo.stateOpt setActiveTexture:(GL_TEXTURE0+ii+progTexBound)];
            glBindTexture(GL_TEXTURE_2D, glTexID);
            CheckGLError("BasicDrawable::drawVBO2() glBindTexture");
            prog->setUniform(baseMapName, (int)ii+progTexBound);
            CheckGLError("BasicDrawable::drawVBO2() glUniform1i");
        }
    }
    
    // If necessary, set up the VAO (once)
    if (basicDraw->vertArrayObj == 0 && basicDraw->sharedBuffer != 0)
        basicDraw->setupVAO(prog);
    
    // Figure out what we're using
    const OpenGLESAttribute *vertAttr = prog->findAttribute("a_position");
    
    // Vertex array
    bool usedLocalVertices = false;
    if (vertAttr && !(basicDraw->sharedBuffer || basicDraw->pointBuffer))
    {
        usedLocalVertices = true;
        glVertexAttribPointer(vertAttr->index, 3, GL_FLOAT, GL_FALSE, 0, &basicDraw->points[0]);
        CheckGLError("BasicDrawable::drawVBO2() glVertexAttribPointer");
        glEnableVertexAttribArray ( vertAttr->index );
        CheckGLError("BasicDrawable::drawVBO2() glEnableVertexAttribArray");
    }
    
    // Other vertex attributes
    const OpenGLESAttribute *progAttrs[basicDraw->vertexAttributes.size()];
    for (unsigned int ii=0;ii<basicDraw->vertexAttributes.size();ii++)
    {
        VertexAttribute *attr = basicDraw->vertexAttributes[ii];
        const OpenGLESAttribute *progAttr = prog->findAttribute(attr->name);
        progAttrs[ii] = NULL;
        if (progAttr)
        {
            // The data hasn't been downloaded, so hook it up directly here
            if (attr->buffer == 0)
            {
                // We have a data array for it, so hand that over
                if (attr->numElements() != 0)
                {
                    glVertexAttribPointer(progAttr->index, attr->glEntryComponents(), attr->glType(), attr->glNormalize(), 0, attr->addressForElement(0));
                    CheckGLError("BasicDrawable::drawVBO2() glVertexAttribPointer");
                    glEnableVertexAttribArray ( progAttr->index );
                    CheckGLError("BasicDrawable::drawVBO2() glEnableVertexAttribArray");
                    
                    progAttrs[ii] = progAttr;
                } else {
                    // The program is expecting it, so we need a default
                    // Note: Could be doing this in the VAO
                    attr->glSetDefault(progAttr->index);
                    CheckGLError("BasicDrawable::drawVBO2() glSetDefault");
                }
            }
        }
    }
    
    // Let a subclass bind anything additional
    basicDraw->bindAdditionalRenderObjects(frameInfo,scene);

    if (instBuffer)
    {
        glBindBuffer(GL_ARRAY_BUFFER,instBuffer);
        const OpenGLESAttribute *thisAttr = prog->findAttribute("a_singleMatrix");
        if (thisAttr)
        {
            for (unsigned int im=0;im<4;im++)
            {
                glVertexAttribPointer(thisAttr->index+im, 4, GL_FLOAT, GL_FALSE, 16*sizeof(GLfloat), (const GLvoid *)(long)(im*(4*sizeof(GLfloat))));
                CheckGLError("BasicDrawableInstance::draw glVertexAttribPointer");
                if (context.API < kEAGLRenderingAPIOpenGLES3)
                    glVertexAttribDivisorEXT(thisAttr->index+im, 0);
                else
                    glVertexAttribDivisor(thisAttr->index+im, 0);
                glEnableVertexAttribArray(thisAttr->index+im);
                CheckGLError("BasicDrawableInstance::setupVAO glEnableVertexAttribArray");
            }
        }
        glBindBuffer(GL_ARRAY_BUFFER,0);
    } else {
        // Set the singleMatrix attribute to identity
        const OpenGLESAttribute *matAttr = prog->findAttribute("a_singleMatrix");
        if (matAttr)
        {
            glVertexAttrib4f(matAttr->index,1.0,0.0,0.0,0.0);
            glVertexAttrib4f(matAttr->index+1,0.0,1.0,0.0,0.0);
            glVertexAttrib4f(matAttr->index+2,0.0,0.0,1.0,0.0);
            glVertexAttrib4f(matAttr->index+3,0.0,0.0,0.0,1.0);
        }
    }
    
    // If we're using a vertex array object, bind it and draw
    if (basicDraw->vertArrayObj)
    {
        glBindVertexArrayOES(basicDraw->vertArrayObj);
        switch (basicDraw->type)
        {
            case GL_TRIANGLES:
                if (instBuffer)
                {
                    if (context.API < kEAGLRenderingAPIOpenGLES3)
                        glDrawElementsInstancedEXT(GL_TRIANGLES, basicDraw->numTris*3, GL_UNSIGNED_SHORT, CALCBUFOFF(basicDraw->sharedBufferOffset,basicDraw->triBuffer), numInstances);
                    else
                        glDrawElementsInstanced(GL_TRIANGLES, basicDraw->numTris*3, GL_UNSIGNED_SHORT, CALCBUFOFF(basicDraw->sharedBufferOffset,basicDraw->triBuffer), numInstances);
                } else
                    glDrawElements(GL_TRIANGLES, basicDraw->numTris*3, GL_UNSIGNED_SHORT, CALCBUFOFF(basicDraw->sharedBufferOffset,basicDraw->triBuffer));
                CheckGLError("BasicDrawable::drawVBO2() glDrawElements");
                break;
            case GL_POINTS:
            case GL_LINES:
            case GL_LINE_STRIP:
            case GL_LINE_LOOP:
                [frameInfo.stateOpt setLineWidth:lineWidth];
                if (instBuffer)
                {
                    if (context.API < kEAGLRenderingAPIOpenGLES3)
                        glDrawArraysInstancedEXT(basicDraw->type, 0, basicDraw->numPoints, numInstances);
                    else
                        glDrawArraysInstanced(basicDraw->type, 0, basicDraw->numPoints, numInstances);
                } else
                    glDrawArrays(basicDraw->type, 0, basicDraw->numPoints);
                CheckGLError("BasicDrawable::drawVBO2() glDrawArrays");
                break;
            case GL_TRIANGLE_STRIP:
                if (instBuffer)
                {
                    if (context.API < kEAGLRenderingAPIOpenGLES3)
                        glDrawArraysInstancedEXT(basicDraw->type, 0, basicDraw->numPoints, numInstances);
                    else
                        glDrawArraysInstanced(basicDraw->type, 0, basicDraw->numPoints, numInstances);
                } else
                    glDrawArrays(basicDraw->type, 0, basicDraw->numPoints);
                CheckGLError("BasicDrawable::drawVBO2() glDrawArrays");
                break;
        }
        glBindVertexArrayOES(0);
    } else {
        // Draw without a VAO
        switch (basicDraw->type)
        {
            case GL_TRIANGLES:
            {
                if (basicDraw->triBuffer)
                {
                    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, basicDraw->triBuffer);
                    CheckGLError("BasicDrawable::drawVBO2() glBindBuffer");
                    if (instBuffer)
                    {
                        if (context.API < kEAGLRenderingAPIOpenGLES3)
                            glDrawElementsInstancedEXT(GL_TRIANGLES, basicDraw->numTris*3, GL_UNSIGNED_SHORT, 0, numInstances);
                        else
                            glDrawElementsInstanced(GL_TRIANGLES, basicDraw->numTris*3, GL_UNSIGNED_SHORT, 0, numInstances);
                    } else
                        glDrawElements(GL_TRIANGLES, basicDraw->numTris*3, GL_UNSIGNED_SHORT, 0);
                    CheckGLError("BasicDrawable::drawVBO2() glDrawElements");
                    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
                } else {
                    if (instBuffer)
                    {
                        if (context.API < kEAGLRenderingAPIOpenGLES3)
                            glDrawElementsInstancedEXT(GL_TRIANGLES, (GLsizei)basicDraw->tris.size()*3, GL_UNSIGNED_SHORT, &basicDraw->tris[0], numInstances);
                        else
                            glDrawElementsInstanced(GL_TRIANGLES, (GLsizei)basicDraw->tris.size()*3, GL_UNSIGNED_SHORT, &basicDraw->tris[0], numInstances);
                    } else
                        glDrawElements(GL_TRIANGLES, (GLsizei)basicDraw->tris.size()*3, GL_UNSIGNED_SHORT, &basicDraw->tris[0]);
                    CheckGLError("BasicDrawable::drawVBO2() glDrawElements");
                }
            }
                break;
            case GL_POINTS:
            case GL_LINES:
            case GL_LINE_STRIP:
            case GL_LINE_LOOP:
                [frameInfo.stateOpt setLineWidth:lineWidth];
                CheckGLError("BasicDrawable::drawVBO2() glLineWidth");
                if (instBuffer)
                {
                    if (context.API < kEAGLRenderingAPIOpenGLES3)
                        glDrawArraysInstancedEXT(basicDraw->type, 0, basicDraw->numPoints, numInstances);
                    else
                        glDrawArraysInstanced(basicDraw->type, 0, basicDraw->numPoints, numInstances);
                } else
                    glDrawArrays(basicDraw->type, 0, basicDraw->numPoints);
                CheckGLError("BasicDrawable::drawVBO2() glDrawArrays");
                break;
            case GL_TRIANGLE_STRIP:
                if (instBuffer)
                {
                    if (context.API < kEAGLRenderingAPIOpenGLES3)
                        glDrawArraysInstancedEXT(basicDraw->type, 0, basicDraw->numPoints, numInstances);
                    else
                        glDrawArraysInstanced(basicDraw->type, 0, basicDraw->numPoints, numInstances);
                } else
                    glDrawArrays(basicDraw->type, 0, basicDraw->numPoints);
                CheckGLError("BasicDrawable::drawVBO2() glDrawArrays");
                break;
        }
    }
    
    // Unbind any textures
    for (unsigned int ii=0;ii<WhirlyKitMaxTextures;ii++)
        if (hasTexture[ii])
        {
            [frameInfo.stateOpt setActiveTexture:(GL_TEXTURE0+ii)];
            glBindTexture(GL_TEXTURE_2D, 0);
        }
    
    // Tear down the various arrays, if we stood them up
    if (usedLocalVertices)
        glDisableVertexAttribArray(vertAttr->index);
    for (unsigned int ii=0;ii<basicDraw->vertexAttributes.size();ii++)
        if (progAttrs[ii])
            glDisableVertexAttribArray(progAttrs[ii]->index);
    
    if (instBuffer)
    {
        const OpenGLESAttribute *thisAttr = prog->findAttribute("a_singleMatrix");
        if (thisAttr)
        {
            for (unsigned int im=0;im<4;im++)
                glDisableVertexAttribArray(thisAttr->index+im);
            CheckGLError("BasicDrawableInstance::draw() glDisableVertexAttribArray");
        }
    }
    
    // Let a subclass clean up any remaining state
    basicDraw->postDrawCallback(frameInfo,scene);

    
#if 0
    whichInstance = -1;
    
    int oldDrawPriority = basicDraw->getDrawPriority();
    RGBAColor oldColor = basicDraw->getColor();
    float oldLineWidth = basicDraw->getLineWidth();
    float oldMinVis,oldMaxVis;
    basicDraw->getVisibleRange(oldMinVis, oldMaxVis);
    
    // Change the drawable
    if (hasDrawPriority)
        basicDraw->setDrawPriority(drawPriority);
    if (hasColor)
        basicDraw->setColor(color);
    if (hasLineWidth)
        basicDraw->setLineWidth(lineWidth);
    if (hasMinVis || hasMaxVis)
        basicDraw->setVisibleRange(minVis, maxVis);
    
    Matrix4f oldMvpMat = frameInfo.mvpMat;
    Matrix4f oldMvMat = frameInfo.viewAndModelMat;
    Matrix4f oldMvNormalMat = frameInfo.viewModelNormalMat;
    
    // No matrices, so just one instance
    if (instances.empty())
        basicDraw->draw(frameInfo,scene);
    else {
        // Run through the list of instances
        for (unsigned int ii=0;ii<instances.size();ii++)
        {
            // Change color
            const SingleInstance &singleInst = instances[ii];
            whichInstance = ii;
            if (singleInst.colorOverride)
                basicDraw->setColor(singleInst.color);
            else {
                if (hasColor)
                    basicDraw->setColor(color);
                else
                    basicDraw->setColor(oldColor);
            }
            
            // Note: Ignoring offsets, so won't work reliably in 2D
            Eigen::Matrix4d newMvpMat = frameInfo.projMat4d * frameInfo.viewTrans4d * frameInfo.modelTrans4d * singleInst.mat;
            Eigen::Matrix4d newMvMat = frameInfo.viewTrans4d * frameInfo.modelTrans4d * singleInst.mat;
            Eigen::Matrix4d newMvNormalMat = newMvMat.inverse().transpose();
            
            // Inefficient, but effective
            Matrix4f mvpMat4f = Matrix4dToMatrix4f(newMvpMat);
            Matrix4f mvMat4f = Matrix4dToMatrix4f(newMvpMat);
            Matrix4f mvNormalMat4f = Matrix4dToMatrix4f(newMvNormalMat);
            frameInfo.mvpMat = mvpMat4f;
            frameInfo.viewAndModelMat = mvMat4f;
            frameInfo.viewModelNormalMat = mvNormalMat4f;
            
            basicDraw->draw(frameInfo,scene);
        }
    }
    
    frameInfo.mvpMat = oldMvpMat;
    frameInfo.viewAndModelMat = oldMvMat;
    frameInfo.viewModelNormalMat = oldMvNormalMat;
    
    // Set it back
    if (hasDrawPriority)
        basicDraw->setDrawPriority(oldDrawPriority);
    if (hasColor)
        basicDraw->setColor(oldColor);
    if (hasLineWidth)
        basicDraw->setLineWidth(oldLineWidth);
    if (hasMinVis || hasMaxVis)
        basicDraw->setVisibleRange(oldMinVis, oldMaxVis);
    
#endif
}
    
}